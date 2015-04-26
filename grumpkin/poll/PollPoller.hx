package grumpkin.poll;

import sys.net.Socket;
#if neko
import neko.net.Poll;
#else
import cpp.net.Poll;
#end


class PollPoller implements IPoller
{
	public var maxConnections:Int;
	public var socketCount(get, never):Int;
	inline function get_socketCount() return sockets.length;

	var sockets:Array<Socket>;
	var _poll:Poll;

	public function new(maxConnections:Int)
	{
		this.maxConnections = maxConnections;
		sockets = [];
		_poll = new Poll(maxConnections);
	}

	public function poll():Null<Array<Socket>>
	{
		return _poll.poll(sockets, 0);
	}

	public function addSocket(socket:Socket):Bool
	{
		if (socketCount >= maxConnections)
			return false;
		sockets.push(socket);
		return true;
	}

	public function removeSocket(socket:Socket)
	{
		sockets.remove(socket);
	}
}
