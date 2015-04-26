package grumpkin.poll;

import sys.net.Socket;
/**
 * The `poll` method should take an array of sockets, and return an array of
 * sockets which are ready to read from or accept a connection from.
 **/
interface IPoller
{
	public var maxConnections:Int;
	public var socketCount(get, never):Int;

	public function poll():Null<Array<Socket>>;
	public function addSocket(socket:Socket):Bool;
	public function removeSocket(socket:Socket):Void;
}
