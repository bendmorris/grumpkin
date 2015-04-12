package grumpkin.poll;

import sys.net.Socket;


class SelectPoller implements IPoller
{
	public var sockets:Array<Socket>;

	public function new() {}

	public function poll():Null<Array<Socket>>
	{
		var ready = Socket.select(sockets, null, sockets, 0);
		if (ready == null) return null;
		return ready.read.concat(ready.others);
	}

	public function addSocket(socket:Socket) {}
	public function removeSocket(socket:Socket) {}
}
