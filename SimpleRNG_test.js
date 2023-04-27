<!DOCTYPE html>
<html>
<body>

<h2>JavaScript Test of IML randomness formula</h2>

<script>
var x = 20000000000000000000;
var y = 30000000000000000000;
var z = 50000000000000000000;

var interval = x + y + z;

var x_times = 0;
var y_times = 0;
var z_times = 0;

console.log(x);
console.log(y);
console.log(z);


for(var i =0; i < 100; i++)
{
	var Rand = Math.random() * 115792089237316195423570985008687907853269984665640564039457584007913129639935; // Max uint
	var RNG = 0;
	if(Rand>interval)
	{
		RNG = Rand % interval;
	}
	else
	{
		RNG = interval % Rand;
	}
	if(RNG < x) x_times++;
	else if(RNG < y + x) y_times++;
	else if(RNG < z + y + x) z_times++;
	else console.log("error");
}

console.log("X times " + x_times);
console.log("Y times " + y_times);
console.log("Z times " + z_times);
</script>

</body>
</html>
