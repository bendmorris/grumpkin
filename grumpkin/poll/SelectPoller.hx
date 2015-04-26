package grumpkin.poll;

import sys.net.Socket;


class SelectPoller implements IPoller
{
	public var maxConnections:Int;
	public var socketCount(get, never):Int;
	inline function get_socketCount() return sockets.length;

	var sockets:Array<Socket>;

	public function new(maxConnections:Int)
	{
		if (maxConnections > 1024)
			throw "Select can only support up to 1024 connections.";
		this.maxConnections = maxConnections;
		sockets = [];
	}

	public function poll():Null<Array<Socket>>
	{
		var ready = Socket.select(sockets, null, sockets, 0);
		if (ready == null) return null;
		return ready.read.concat(ready.others);
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
