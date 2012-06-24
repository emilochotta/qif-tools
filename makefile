
test: Ticker.testout

Ticker.testout: AssetClass.pm Ticker.pm Ticker.t
	perl Ticker.t > Ticker.testout
	cat Ticker.testout

clean:
	rm *.testout
