package grumpkin.poll;

import sys.net.Socket;


class SelectPoller implements IPoller
{
	public var socketCount(get, never):Int;
	inline function get_socketCount() return sockets.length;

	var sockets:Array<Socket>;

	public function new()
	{
		sockets = [];
	}

	public function poll():Null<Array<Socket>>
	{
		var ready = Socket.select(sockets, null, sockets, 0);
		if (ready == null) return null;
		return ready.read.concat(ready.others);
	}

	public function addSocket(socket:Socket)
	{
		sockets.push(socket);
	}

	public function removeSocket(socket:Socket)
	{
		sockets.remove(socket);
	}
}
