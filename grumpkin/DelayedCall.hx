package grumpkin;


class DelayedCall extends LoopingCall
{
	public function new(f, seconds)
	{
		super(f, seconds, 1);
	}
}
