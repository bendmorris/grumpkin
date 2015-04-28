package grumpkin;


class LoopingCall implements IUpdater
{
	public var f:Void->Void;
	public var seconds:Float;
	public var elapsed:Float;
	public var lastCheck:Float;
	public var maxLoops:Int;
	public var loops:Int;
	public var stopped:Bool = false;

	public var nextUpdate(get, never):Float;
	function get_nextUpdate() return seconds - elapsed;

	public function new(f, seconds, ?maxLoops=0)
	{
		this.f = f;
		this.seconds = seconds;
		this.maxLoops = maxLoops;

		elapsed = 0;
		lastCheck = haxe.Timer.stamp();

		loops = 0;
	}

	public function stop() stopped = true;

	public function update()
	{
		if (stopped) return false;

		var currentTime = haxe.Timer.stamp();
		if (seconds > 0) elapsed += currentTime - lastCheck;
		lastCheck = currentTime;

		if (elapsed >= seconds)
		{
			f();
			elapsed -= seconds;

			if (maxLoops > 0)
			{
				if (++loops >= maxLoops)
					return false;
			}
		}

		return true;
	}
}
