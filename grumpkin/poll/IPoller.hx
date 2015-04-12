package grumpkin.poll;

import sys.net.Socket;
/**
 * The `poll` method should take an array of sockets, and return an array of
 * sockets which are ready to read from or accept a connection from.
 **/
interface IPoller
{
	public var sockets:Array<Socket>;

	public function poll():Null<Array<Socket>>;
	public function addSocket(socket:Socket):Void;
	public function removeSocket(socket:Socket):Void;
}
