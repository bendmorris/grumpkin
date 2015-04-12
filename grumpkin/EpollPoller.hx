package grumpkin;

import sys.net.Socket;
#if neko
import neko.net.Epoll;
#else
import cpp.net.Epoll;
#end


class EpollPoller implements IPoller
{
	public var sockets:Array<Socket>;
	var _epoll:Epoll;

	public function new(maxConnections:Int, maxEvents:Int)
	{
		_epoll = new Epoll(maxConnections, maxEvents);
	}

	public function poll():Null<Array<Socket>>
	{
		var eventData = _epoll.poll(0);
		if (events == null) return null;
		return [for (event in eventData) event.socket];
	}

	public function addSocket(socket:Socket)
	{
		_epoll.register(socket);
	}
	public function removeSocket(socket:Socket)
	{
		_epoll.unregister(socket);
	}
}
