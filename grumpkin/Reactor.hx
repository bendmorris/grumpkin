package grumpkin;

import haxe.ds.Vector;
import haxe.io.Eof;
import haxe.io.Error;
import sys.net.Socket;
#if neko
import neko.vm.Deque;
import neko.vm.Thread;
import neko.vm.Mutex;
#elseif cpp
import cpp.vm.Deque;
import cpp.vm.Thread;
import cpp.vm.Mutex;

@:headerCode("#include <csignal>")
@:cppFileCode("
void _handler(int sig) {
	grumpkin::Reactor_obj::_reactor->stop();
}
")
#end


class Reactor
{
	static var _reactor:Null<Reactor> = null;
	public static var reactor(get, never):Null<Reactor>;
	static function get_reactor()
	{
		if (_reactor == null)
		{
			_reactor = new grumpkin.reactor.SelectReactor(1024);
		}
		return _reactor;
	}

	public var socketCount(get, never):Int;
	function get_socketCount() return -1;

	public var maxConnections:Int;
	public var nworkers:Int;
	public var connectWait:Float;
	public var maxPendingConnections:Int;
	public var errorOutput:haxe.io.Output;
	public var maxUpdatesPerSecond:Float;
	public var maxWorkCyclesPerSecond:Float;

	public var running:Bool = false;

	public var listeners:Map<Socket, IProtocol>;
	public var clients:Map<Socket, IProtocol>;

	var initialized:Bool = false;

	var workers:Vector<Thread>;
	var nextWorker:Int = 0;
	var workerMutex:Mutex = new Mutex();

	var updaters:Deque<IUpdater>;
	var recycledUpdaters:Deque<IUpdater>;

	var lastUpdate:Float = 0;

	// this is an abstract class; use one of the grumpkin.reactor.* classes that
	// extends it instead
	function new()
	{
		if (_reactor != null)
			throw "Another reactor exists.";
		_reactor = this;

		maxConnections = 1024;
		nworkers = 8;
		connectWait = 0.01;
		maxPendingConnections = 64;
		errorOutput = Sys.stderr();
		maxUpdatesPerSecond = 300;
		maxWorkCyclesPerSecond = 60;

		listeners = new Map();
		clients = new Map();
		updaters = new Deque();
		recycledUpdaters = new Deque();

		lastUpdate = haxe.Timer.stamp();
	}

	public function init()
	{
		if (initialized) return;

		if (nworkers > 0)
		{
			workers = new Vector(nworkers);
			for (i in 0 ... nworkers)
			{
				workers[i] = Thread.create(runWorker);
			}
		}
		initialized = true;
	}

	public function listen(protocol:IProtocol)
	{
		listeners[protocol.listener] = protocol;
		protocol.listener.listen(maxPendingConnections);
		addSocket(protocol.listener);
	}

	/**
	 * Begin the reactor's main loop.
	 */
	public function run()
	{
#if cpp
		untyped __cpp__("signal(SIGINT, &_handler);");
#end
		init();

		running = true;
		var wait:Null<Float> = null;
		while (running)
		{
			var startTime = haxe.Timer.stamp();

			// check for new messages, connections or disconnections
			processEvents(wait);

			// update all attached updaters
			var updater:IUpdater;
			var newUpdaters = recycledUpdaters;
			wait = 1 / maxUpdatesPerSecond;
			while ((updater = updaters.pop(false)) != null)
			{
				if (updater.update()) newUpdaters.push(updater);
				// poll for new socket events until an updater is ready
				var nextUpdate = updater.nextUpdate;
				if (nextUpdate != null && (wait == null || nextUpdate < wait))
					wait = nextUpdate;
			}
			// recycle updaters that are still running
			recycledUpdaters = updaters;
			updaters = newUpdaters;

			lastUpdate = startTime;
		}

		onClose();
	}

	public function stop() running = false;

	public function addClient(socket:Socket, protocol:IProtocol)
	{
		clients[socket] = protocol;
		addSocket(socket);
	}

	/**
	 * Poll for new connections or messages.
	 */
	function processEvents(wait:Null<Float>)
	{
		try
		{
			var ready = poll(wait);

			if (ready != null)
			{
				for (s in ready)
				{
					if (s == null) continue;

					if (listeners.exists(s))
					{
						// this is a listening socket
						for (i in 0 ... maxPendingConnections)
						{
							if (socketCount >= maxConnections)
								break;

							// check for a new connection
							try
							{
								var sock = s.accept();
								var added = listeners[s].addClient(sock);
								if (added)
								{
									addClient(sock, listeners[s]);
								}
								else
								{
									sock.close();
								}
							}
							catch (e:Dynamic)
							{
								break;
							}
						}
					}
					else
					{
						// this is a connected client
						try
						{
							// received data from client
							var protocol:IProtocol = clients[s];
							protocol.clientMessageReady(s);
						}
						catch (e:Dynamic)
						{
							// client disconnected
							if (!Std.is(e, Eof))
								logError(e);

							stopClient(s);
						}
					}
				}
			}
		}
		catch (e:Dynamic)
		{
			logError(e);
		}
	}

	/**
	 * Wait up to `wait` seconds, then return an array of sockets ready to read
	 * or accept connections from, or null if no result. Should be overridden.
	 */
	function poll(?wait:Float):Null<Array<Socket>>
	{
		Sys.sleep(wait);
		return null;
	}

	public function addSocket(s:Socket):Bool return false;

	public function removeSocket(s:Socket)
	{
		if (clients.exists(s))
		{
			clients.remove(s);
		}
	}

	/**
	 * Disconnect the client using this socket.
	 */
	public function stopClient(s:Socket)
	{
		try s.shutdown(true, true) catch(e:Dynamic) {}
		try s.close() catch (e:Dynamic) {}

		if (clients.exists(s))
		{
			clients[s].disconnectClient(s);
			removeSocket(s);
		}
	}

	/**
	 * Call function f in the next available worker thread; when finished, call
	 * onSuccess with the return value in the main thread. If nworkers = 0, f
	 * will be called in the same thread (immediately) instead.
	 */
	public function defer(f:Void->Dynamic, ?onSuccess:Dynamic->Void, ?onError:Void->Void)
	{
		try
		{
			if (nworkers > 0)
			{
				// assign the next worker thread to run this function
				workerMutex.acquire();
				var worker = workers[nextWorker++];
				if (nextWorker >= nworkers) nextWorker %= nworkers;
				workerMutex.release();
				worker.sendMessage(doDeferred.bind(f, onSuccess, onError));
			} else doDeferred(f, onSuccess, onError);
		}
		catch (e:Dynamic)
		{
			logError(e);
			workerMutex.release();
		}
	}

	/**
	 * Call f every `seconds` seconds, optionally stopping after `maxLoops`
	 * calls.
	 */
	public function loopingCall(f:Void->Void, seconds:Float, ?maxLoops:Int=0):LoopingCall
	{
		return cast addUpdater(new LoopingCall(f, seconds, maxLoops));
	}

	/**
	 * Wait `seconds` seconds, then call f.
	 */
	public function callLater(f:Void->Void, seconds:Float):DelayedCall
	{
		return cast addUpdater(new DelayedCall(f, seconds));
	}

	/**
	 * Generic method to add an implementer of the IUpdater interface to the
	 * server's update loop.
	 */
	public function addUpdater(updater:IUpdater):IUpdater
	{
		updaters.push(updater);
		return updater;
	}

	/**
	 * Send data to a connected socket. If this method fails, disconnect the
	 * client.
	 */
	public function sendData(s:Socket, data:String)
	{
		work(s.write.bind(data), null, reactor.stopClient.bind(s));
	}

	/**
	 * Call function f in the next available worker thread. If nworkers = 0,
	 * f will be called in the same thread (immediately) instead.
	 */
	public function work(f:Void->Void, ?onSuccess:Void->Void, ?onError:Void->Void)
	{
		try
		{
			if (nworkers > 0)
			{
				// assign the next worker thread to run this function
				workerMutex.acquire();
				var worker = workers[nextWorker++];
				if (nextWorker >= nworkers) nextWorker %= nworkers;
				workerMutex.release();
				worker.sendMessage(doWork.bind(f, onSuccess, onError));
			} else doWork(f, onSuccess, onError);
		}
		catch (e:Dynamic)
		{
			logError(e);
			workerMutex.release();
		}
	}

	function runWorker()
	{
		while (true)
		{
			var startTime = haxe.Timer.stamp();

			var f = Thread.readMessage(true);
			try
			{
				f();
			}
			catch (e:Dynamic)
			{
				logError(e);
			}

			var elapsed = haxe.Timer.stamp() - startTime;
			if (elapsed < 1 / maxWorkCyclesPerSecond)
				Sys.sleep(1 / maxWorkCyclesPerSecond - elapsed);
		}
	}

	function doWork(f:Void->Void, onSuccess:Void->Void, onError:Void->Void)
	{
		try
		{
			f();
			if (onSuccess != null) callLater(onSuccess, 0);
		}
		catch (e:Dynamic)
		{
			logError(e);
			if (onError != null) callLater(onError, 0);
		}
	}

	function doDeferred(f:Void->Dynamic, onSuccess:Dynamic->Void, onError:Void->Void)
	{
		try
		{
			var result = f();
			if (onSuccess != null) callLater(onSuccess.bind(result), 0);
		}
		catch (e:Dynamic)
		{
			logError(e);
			if (onError != null) callLater(onError, 0);
		}
	}

	public function logError(e:Dynamic)
	{
		var stack = haxe.CallStack.exceptionStack();
		onError(e, stack);
	}

	// --- CUSTOMIZABLE API ---

	/**
	 * Called when an error is encountered.
	 */
	public dynamic function onError(e:Dynamic, stack)
	{
		var estr = try Std.string(e) catch (e2:Dynamic) "???" + try "[" + Std.string(e2) + "]" catch(e:Dynamic) "";
		errorOutput.writeString(estr + "\n" + haxe.CallStack.toString(stack) + "\n");
		errorOutput.flush();
#if debug
		throw e;
#end
	}

	/**
	 * Called before exiting.
	 */
	public dynamic function onClose() {}
}
