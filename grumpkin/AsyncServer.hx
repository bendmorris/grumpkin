package grumpkin;

import haxe.ds.Vector;
import haxe.io.Bytes;
import haxe.io.Eof;
import haxe.io.Error;
import sys.net.Socket;
import sys.net.Host;
#if neko
import neko.vm.Deque;
import neko.vm.Thread;
import neko.vm.Mutex;
#else
import cpp.vm.Deque;
import cpp.vm.Thread;
import cpp.vm.Mutex;
#end
import grumpkin.poll.IPoller;


typedef ClientInfo<Client> = {
	var client:Client;
	var sock:Socket;
	var buf:Bytes;
	var bufpos:Int;
}

class AsyncServer<Client, Message>
{
	public var running:Bool = false;

	public var maxConnections:Int;
	public var listen:Int;
	public var nworkers:Int;
	public var connectWait:Float;
	public var errorOutput:haxe.io.Output;
	public var initialBufferSize:Int;
	public var maxBufferSize:Int;
	public var messageHeaderSize:Int;
	public var maxUpdatesPerSecond:Float;
	public var maxWorkCyclesPerSecond:Float;

	var serverSocket:Socket;
	var poller:IPoller;

	var workers:Vector<Thread>;
	var nextWorker:Int = 0;
	var workerMutex:Mutex = new Mutex();

	var updaters:Deque<IUpdater>;
	var recycledUpdaters:Deque<IUpdater>;

	public function new()
	{
		maxConnections = 1024;
		nworkers = 8;
		messageHeaderSize = 1;
		listen = 10;
		connectWait = 0.01;
		errorOutput = Sys.stderr();
		initialBufferSize = (1 << 10);
		maxBufferSize = (1 << 16);
		maxUpdatesPerSecond = 1200;
		maxWorkCyclesPerSecond = 60;

		updaters = new Deque();
		recycledUpdaters = new Deque();
	}

	function init()
	{
		if (nworkers > 0)
		{
			workers = new Vector(nworkers);
			for (i in 0 ... nworkers)
			{
				workers[i] = Thread.create(runWorker);
			}
		}
	}

	/**
	 * Start the server, listening on host:port, optionally with a custom
	 * polling mechanism.
	 */
	public function run(host, port, ?poller:IPoller)
	{
		// set up poller
		if (poller == null)
		{
			// select is cross-platform; on other platforms, a more efficient
			// poller should be used
			this.poller = new grumpkin.poll.SelectPoller();
		}
		else this.poller = poller;

		// socket to listen for new connections
		serverSocket = new Socket();
		serverSocket.setBlocking(false);
		serverSocket.bind(new Host(host), port);
		serverSocket.listen(listen);
		addSocket(serverSocket);

		init();

		// main loop
		running = true;
		while (running)
		{
			var startTime = haxe.Timer.stamp();

			// check for new messages, connections or disconnections
			runPoll();

			var updater:IUpdater;
			var newUpdaters = recycledUpdaters;
			while ((updater = updaters.pop(false)) != null)
			{
				if (updater.update()) newUpdaters.push(updater);
			}
			recycledUpdaters = updaters;
			updaters = newUpdaters;

			var elapsed = haxe.Timer.stamp() - startTime;
			if (elapsed < 1 / maxUpdatesPerSecond)
				Sys.sleep(1 / maxUpdatesPerSecond - elapsed);
		}
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
	 * Create a new ClientInfo for a connected client.
	 */
	public function addClient(s:Socket)
	{
		s.setBlocking(false);

		if (poller.socketCount < maxConnections + 1)
		{
			var client = clientConnected(s);
			if (client == null)
				return refuseClient(s);

			var clientInfo:ClientInfo<Client> = {
				client: client,
				sock: s,
				buf: Bytes.alloc(initialBufferSize),
				bufpos: 0,
			};
			s.custom = clientInfo;
			addSocket(s);
		}
		else refuseClient(s);
	}

	/**
	 * Send data to a connected socket. If this method fails, disconnect the
	 * client.
	 */
	public function sendData(s:Socket, data:String)
	{
		work(s.write.bind(data), null, stopClient.bind(s));
	}

	/**
	 * Disconnect the client using this socket.
	 */
	public function stopClient(s:Socket)
	{
		var clientInfo:ClientInfo<Client> = s.custom;
		try s.shutdown(true, true) catch(e:Dynamic) {}
		try s.close() catch (e:Dynamic) {}
		removeSocket(s);
		clientDisconnected(clientInfo.client);
	}

	/**
	 * Shut down the server. This is a soft shutdown; the server will finish
	 * the current iteration of the main loop before stopping.
	 */
	public function shutdown()
	{
		running = false;
	}

	/**
	 * When a client socket has data to be read, check for complete messages
	 * and process them.
	 */
	function readClientData(c:ClientInfo<Client>)
	{
		var available = c.buf.length - c.bufpos;

		if (available == 0)
		{
			var newsize = c.buf.length * 2;
			if (newsize > maxBufferSize)
			{
				newsize = maxBufferSize;
				if( c.buf.length == maxBufferSize )
					throw "Max buffer size reached";
			}
			var newbuf = Bytes.alloc(newsize);
			newbuf.blit(0, c.buf, 0, c.bufpos);
			c.buf = newbuf;
			available = newsize - c.bufpos;
		}

		var bytes = c.sock.input.readBytes(c.buf, c.bufpos, available);
		var pos = 0;
		var len = c.bufpos + bytes;
		while (len >= messageHeaderSize)
		{
			var m = readClientMessage(c.client, c.buf, pos, len);
			if( m == null )
				break;
			pos += m.bytes;
			len -= m.bytes;
			clientMessage(c.client, m.msg);
		}
		if (pos > 0)
			c.buf.blit(0,c.buf,pos,len);
		c.bufpos = len;
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

	function logError(e:Dynamic)
	{
		var stack = haxe.CallStack.exceptionStack();
		onError(e, stack);
	}

	function refuseClient(s:Socket)
	{
		// we have reached maximum number of active clients
		s.close();
	}

	function runPoll()
	{
		try
		{
			var ready = poller.poll();

			if (ready != null)
			{
				for (s in ready)
				{
					if (s == serverSocket)
					{
						// new connection
						addClient(serverSocket.accept());
					}
					else
					{
						var info:ClientInfo<Client> = s.custom;
						try
						{
							// received data from client
							readClientData(info);
						}
						catch (e:Dynamic)
						{
							// client disconnected
							if (!Std.is(e, Eof) && !Std.is(e, Error))
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

	function addSocket(socket:Socket)
	{
		poller.addSocket(socket);
	}

	function removeSocket(socket:Socket)
	{
		poller.removeSocket(socket);
	}

	// --- CUSTOMIZABLE API ---

	/**
	 * Called when an error is encountered.
	 */
	public dynamic function onError(e:Dynamic, stack)
	{
		var estr = try Std.string(e) catch( e2 : Dynamic ) "???" + try "["+Std.string(e2)+"]" catch( e : Dynamic ) "";
		errorOutput.writeString( estr + "\n" + haxe.CallStack.toString(stack) );
		errorOutput.flush();
	}

	/**
	 * Called when a new client is connected. Should return a Client instance
	 * if the new client can be created; if this method returns null, the
	 * connection will be refused.
	 */
	public dynamic function clientConnected(s:Socket):Client
		return null;

	/**
	 * Called when a client is disconnected.
	 */
	public dynamic function clientDisconnected(c:Client) {}

	/**
	 * Called when data is ready to be read; this method should read from the
	 * provided buffer starting at position `pos`. If a complete message has
	 * been received, return the message and its length in bytes, and
	 * clientMessage will be called on the resulting message. If msg is null,
	 * the data will remain in the buffer until more is received.
	 */
	public dynamic function readClientMessage(c:Client, buf:Bytes, pos:Int, len:Int):{msg:Message, bytes:Int}
	{
		return {
			msg : null,
			bytes : len,
		};
	}

	/**
	 * Process a complete message from the client.
	 */
	public dynamic function clientMessage(c:Client, msg:Message) {}
}
