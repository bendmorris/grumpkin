package grumpkin.poll;

import sys.net.Socket;
#if neko
import neko.net.Poll;
#else
import cpp.net.Poll;
#end


class PollPoller implements IPoller
{
	public var sockets:Array<Socket>;
	var _poll:Poll;

	public function new(maxConnections:Int)
	{
		_poll = new Poll(maxConnections);
	}

	public function poll():Null<Array<Socket>>
	{
		return _poll.poll(sockets, 0);
	}

	public function addSocket(socket:Socket) {}
	public function removeSocket(socket:Socket) {}
}
