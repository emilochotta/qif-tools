
PM_FILES := \
	Account.pm \
	AssetAllocation.pm \
	AssetCategory.pm \
	AssetClass.pm \
	Holding.pm \
	Portfolio.pm \
	RebalTran.pm \
	Ticker.pm \
	Transaction.pm \
	Transactions.pm \
	Util.pm

TESTOUT_FILES := $(PM_FILES:.pm=.testout)

all: test qif2mstar_out.txt

test: $(TESTOUT_FILES)

%.testout : %.t
	perl $< > $@

Account.testout: $(PM_FILES) Account.t
Holding.testout: $(PM_FILES) Holding.t
Portfolio.testout: $(PM_FILES) Portfolio.t
Transaction.testout: $(PM_FILES) Transaction.t
Transactions.testout: $(PM_FILES) Transactions.t
Ticker.testout: $(PM_FILES) Ticker.t
Util.testout: $(PM_FILES) Util.t

qif2mstar_out.txt: Qif2Mstar.pl $(PM_FILES)
	perl Qif2Mstar.pl > $@
	cat $@

.PHONY: clean
clean:
	-rm *.testout qif2mstar_out.txt
