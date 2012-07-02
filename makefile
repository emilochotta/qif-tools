
PM_FILES := \
	Account.pm \
	Holding.pm \
	Transaction.pm \
	Transactions.pm \
	Ticker.pm \
	Util.pm

TESTOUT_FILES := $(PM_FILES:.pm=.testout)

test: $(TESTOUT_FILES)

%.testout : %.t
	perl $< > $@
	cat $@

Account.testout: $(PM_FILES) Account.t
Holding.testout: $(PM_FILES) Holding.t
Transaction.testout: $(PM_FILES) Transaction.t
Transactions.testout: $(PM_FILES) Transactions.t
Ticker.testout: $(PM_FILES) Ticker.t
Util.testout: $(PM_FILES) Util.t

.PHONY: clean
clean:
	-rm *.testout
