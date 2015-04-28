package grumpkin;

import haxe.io.Bytes;
import sys.net.Socket;
import sys.net.Host;


typedef ClientInfo<Client> = {
	var client:Client;
	var sock:Socket;
	var buf:Bytes;
	var bufpos:Int;
}

class Protocol<Client, Message> implements IProtocol
{
	public var running:Bool = false;

	public var messageHeaderSize:Int;
	public var initialBufferSize:Int;
	public var maxBufferSize:Int;

	public var listener:Socket;
	var reactor:Reactor;

	// this is an abstract class; use one of the grumpkin.protocol.* classes that
	// extends it, or create your own
	function new()
	{
		messageHeaderSize = 1;
		initialBufferSize = (1 << 10);
		maxBufferSize = (1 << 16);
	}

	/**
	 * Start the server, listening on host:port, optionally with a custom
	 * polling mechanism.
	 */
	public function listen(host:String, port:Int)
	{
		// socket to listen for new connections
		listener = new Socket();
		listener.setBlocking(false);
		listener.bind(new Host(host), port);

		Reactor.reactor.listen(this);
	}

	/**
	 * Create a new ClientInfo for a connected client.
	 */
	public function addClient(s:Socket):Bool
	{
		s.setBlocking(false);

		var client = clientConnected(s);
		if (client == null)
		{
			return false;
		}

		var clientInfo:ClientInfo<Client> = {
			client: client,
			sock: s,
			buf: Bytes.alloc(initialBufferSize),
			bufpos: 0,
		};
		s.custom = clientInfo;
		return true;
	}

	public function clientMessageReady(s:Socket) readClientData(s.custom);

	/**
	 * When a client socket has data to be read, check for complete messages
	 * and process them.
	 */
	function readClientData(c:ClientInfo<Client>)
	{
		var available = c.buf.length - c.bufpos;

		if (available == 0)
		{
			var newsize = c.buf.length * 2;
			if (newsize > maxBufferSize)
			{
				newsize = maxBufferSize;
				if( c.buf.length == maxBufferSize )
					throw "Max buffer size reached";
			}
			var newbuf = Bytes.alloc(newsize);
			newbuf.blit(0, c.buf, 0, c.bufpos);
			c.buf = newbuf;
			available = newsize - c.bufpos;
		}

		var bytes = c.sock.input.readBytes(c.buf, c.bufpos, available);
		var pos = 0;
		var len = c.bufpos + bytes;

		while (len >= messageHeaderSize)
		{
			var m = readClientMessage(c.client, c.buf, pos, len);
			if( m == null )
				break;
			pos += m.bytes;
			len -= m.bytes;
			clientMessage(c.client, m.msg);
		}
		if (pos > 0)
			c.buf.blit(0,c.buf,pos,len);
		c.bufpos = len;
	}

	public function disconnectClient(socket:Socket)
	{
		var clientInfo:ClientInfo<Client> = socket.custom;
		clientDisconnected(clientInfo.client);
	}

	// --- CUSTOMIZABLE API ---

	/**
	 * Called when a new client is connected. Should return a Client instance
	 * if the new client can be created; if this method returns null, the
	 * connection will be refused.
	 */
	public dynamic function clientConnected(s:Socket):Client
		return null;

	/**
	 * Called when a client is disconnected.
	 */
	public dynamic function clientDisconnected(c:Client) {}

	/**
	 * Called when data is ready to be read; this method should read from the
	 * provided buffer starting at position `pos`. If a complete message has
	 * been received, return the message and its length in bytes, and
	 * clientMessage will be called on the resulting message. If msg is null,
	 * the data will remain in the buffer until more is received.
	 */
	public dynamic function readClientMessage(c:Client, buf:Bytes, pos:Int, len:Int):{msg:Message, bytes:Int}
	{
		return {
			msg : null,
			bytes : len,
		};
	}

	/**
	 * Process a complete message from the client.
	 */
	public dynamic function clientMessage(c:Client, msg:Message) {}
}
