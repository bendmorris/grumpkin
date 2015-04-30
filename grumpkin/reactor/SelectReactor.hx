package grumpkin.reactor;

import sys.net.Socket;
import grumpkin.Reactor;


class SelectReactor extends Reactor
{
	override function get_socketCount() return sockets.length;

	var sockets:Array<Socket>;

	public function new(maxConnections:Int)
	{
		super();

		this.maxConnections = maxConnections;
		sockets = [];
	}

	override function poll(wait:Float):Null<Array<Socket>>
	{
		var ready = Socket.select(sockets, null, null, 0);
		if (ready == null) return null;
		return ready.read;
	}

	override public function addSocket(socket:Socket):Bool
	{
		if (socketCount >= maxConnections)
			return false;
		sockets.push(socket);
		return true;
	}

	override public function removeSocket(socket:Socket)
	{
		super.removeSocket(socket);
		sockets.remove(socket);
	}
}
