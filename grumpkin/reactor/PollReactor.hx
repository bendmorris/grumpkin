package grumpkin.reactor;

import sys.net.Socket;
#if neko
import neko.net.Poll;
#else
import cpp.net.Poll;
#end
import grumpkin.Reactor;


class PollReactor extends Reactor
{
	override function get_socketCount() return sockets.length;

	var sockets:Array<Socket>;
	var _poll:Poll;

	public function new(maxConnections:Int)
	{
		super();

		this.maxConnections = maxConnections;
		sockets = [];
		_poll = new Poll(maxConnections);
	}

	override function poll(?wait:Float):Null<Array<Socket>>
	{
		return _poll.poll(sockets, wait == null ? 0 : wait);
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
