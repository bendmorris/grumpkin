package grumpkin.poll;

import sys.net.Socket;
#if neko
import neko.net.Epoll;
#else
import cpp.net.Epoll;
#end


class EpollPoller implements IPoller
{
	public var socketCount(get, never):Int;
	inline function get_socketCount() return _socketCount;

	var sockets:Map<Socket, Bool>;
	var _epoll:Epoll;
	var _maxEvents:Int;
	var _socketCount:Int;

	public function new(maxEvents:Int)
	{
		sockets = new Map();
		_epoll = new Epoll();
		_maxEvents = maxEvents;
		_socketCount = 0;
	}

	public function poll():Null<Array<Socket>>
	{
		if (_socketCount > 0) return _epoll.wait(_maxEvents, 0);
		else return null;
	}

	public function addSocket(socket:Socket)
	{
		if (!sockets.exists(socket))
		{
			_epoll.register(socket);
			sockets[socket] = true;
			++_socketCount;
		}
	}

	public function removeSocket(socket:Socket)
	{
		if (sockets.exists(socket))
		{
			_epoll.unregister(socket);
			sockets.remove(socket);
			--_socketCount;
		}
	}
}
