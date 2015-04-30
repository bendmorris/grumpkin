package grumpkin.reactor;

import sys.net.Socket;
#if neko
import neko.net.Epoll;
#else
import cpp.net.Epoll;
#end


class EpollReactor extends Reactor
{
	override function get_socketCount() return _socketCount;

	var sockets:Map<Socket, Bool>;
	var _epoll:Epoll;
	var _maxEvents:Int;
	var _socketCount:Int;

	public function new(maxConnections:Int, ?maxEvents:Int=128)
	{
		super();

		this.maxConnections = maxConnections;
		sockets = new Map();
		_epoll = new Epoll(maxEvents);
		_maxEvents = maxEvents;
		_socketCount = 0;
	}

	override function poll(wait:Float):Null<Array<Socket>>
	{
		if (_socketCount > 0) return _epoll.wait(wait);
		else return null;
	}

	override public function addSocket(socket:Socket):Bool
	{
		if (socketCount >= maxConnections)
			return false;

		if (!sockets.exists(socket))
		{
			_epoll.register(socket);
			sockets[socket] = true;
			++_socketCount;
			return true;
		}
		return false;
	}

	override public function removeSocket(socket:Socket)
	{
		super.removeSocket(socket);
		if (sockets.exists(socket))
		{
			_epoll.unregister(socket);
			sockets.remove(socket);
			--_socketCount;
		}
	}
}
