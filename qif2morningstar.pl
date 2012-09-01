#!/bin/perl

#
# See "Uploading to Morningstar"
#
# TODO: Rewrite a bunch of this using the objects I've recently created.
#

package Qif2Morningstar;
require Exporter;
@ISA = qw(Exporter);
@EXPORT_OK = qw();

use Finance::QIF;
use Text::CSV_XS;
use Time::Format qw(%time time_format);
use Date::Calc qw(Delta_Days);
use Portfolio;
use AssetAllocation;
use strict;
use warnings;

# our @QColHeaders = (
#     'date',
#     'action',
#     'security',
#     'price',
#     'quantity',
#     'transaction',
#     'status',
#     'text',
#     'memo',
#     'commission',
#     'account',
#     'amount',
#     'total'
#     );

my $security = 'security';
my $prices = 'prices';
my $symbol = 'symbol';
my $Shares = 'Shares/Ratio';

# These are headers in the CSV file that morningstar import understands
our @MstarHeaders = (
    'Ticker',
    'File',
    'Date',
    'Action',
    'Name',
    'Price',
    $Shares,
    'Comm',
    'Amount',
    'Running'
    );

# Map from quicken fields to morningstar fields
our %ToMstar = (
    'file' => 'File',
    'date' => 'Date',
    'action' => 'Action',
    'security' => 'Name',
    'price' => 'Price',
    'quantity' => $Shares,
    'transaction' => 'Amount',
    'status' => 'status',
    'text' => 'text',
    'memo' => 'memo',
    'commission' => 'Comm',
    'account' => 'account',
    'amount' => 'transferred',
    'total' => 'total'
    );

# Map from portfolio name to list of QIF file basenames (no
# .QIF). This was introduced 4/28/2012.  It brings some problems
# because the data isn't organized on a per-account basis.  So, you
# need to include all accounts that have or had a given security.  For
# example, FAIRX bought in schwab-emil-401K but sold in
# schwab-emil-ira, which is now closed.  The pruning function works
# across all accounts, so the missing sell transaction causes the
# totals to mismatch.
our %PortfolioDefs = (
    'all' => [
	'etrade-ira',
	'etrade-joint',
	'etrade-5557',
	'etrade',
	'schwab-annabelle',
	'schwab-bin-ira',
	'schwab-bin401k',
	'schwab-emil-ira',
	'schwab-emil',
	'schwab-roth-ira',
	'schwab-shawhu',
	'van-brokerage',
	'van-goog-401k',
	'van-mut-funds',
	'van-rollover-ira',
	'van-roth-brokerage',
	'van-roth-mfs',
	'van-trad-ira-brok',
    ],	
    'me' => [
	'etrade-ira',
	'etrade-joint',
	'etrade-5557',
	'etrade',
	'schwab-bin-ira',
	'schwab-emil-ira',  # Needed for VWO
	'schwab-emil',
	'schwab-roth-ira',
	'van-brokerage',
	'van-mut-funds',
	'van-rollover-ira',
	'van-roth-brokerage',
	'van-roth-mfs',
	'van-trad-ira-brok',
    ],	
    'amo' => [
	'schwab-annabelle',
    ],	
    'nso' => [
	'schwab-nicholas',
    ],	
    'bin' => [
	'schwab-bin401k',
    ],	
    'goog' => [
	'van-goog-401k',
    ],	
    );

#
# Every ticker ever purchased should be either in Skip or in Tickers
#
our %Skip = (
    '2004-07 DP407070 Bin' => '1', # ESO
    '2007-07 FS783025 Bin' => '1', # ESO
    '-Cash-' => '1',
    'TOTAL Investments' => '1',
    'A' => '1',
    'AGERE SYSTEMS INC CL A' => '1',
    'AGERE SYSTEMS INC CLASS B' => '1',
    'ALPINE REALTY INCOME & GROWTH FUND/Y' => 'AIGYX',
    'ALPINE U.S. REAL ESTATE EQUITY FUND CLASS Y' => 'EUEYX',
    'AMERICAN AADVANTAGE SMALL CAP VALUE/PLANAHEAD' => 'AVPAX',
    'AMERICAN CENTURY INTERNATIONAL BOND/INV' => 'BEGBX',
    'AMERICAN CENTURY VISTA/INV' => 'TWCVX',
    'AMERICAN CENTURY TARGET MATURITY 2025/INV' => 'BTTRX',
    'ANALOG DEVICES INC' => '1',
    'APPLIED MICRO CIRCUITS CORP' => '1',
    'ARTISAN INTL VALUE FUND' => 'ARTKX',
    'ARTISAN MIDCAP VALUE FD' => 'ARTQX',
    'AV' => '1',
    'AVAYA INC            XXX' => '1',
    'Ac=' => '1',
    'Amazon.com' => '1',
    'Applied Materials' => '1',
    'BARON IOPPORTUNITY FUND' => 'BIOPX',
    'BERKSHIRE HATHAWAY CL B' => 'BRK.B',
    'BERKSHIRE FOCUS FUND' => 'BFOCX',
    'BROADCOM CORP CL A' => '1',
    'CA PORTFOLIO 2018 (INDEX)' => '',
    'CA PORTFOLIO 2021 (INDEX)' => '',
    'CALL XILINX INC$21 EXP 08/22/09' => '',
    'CALL XILINX INC$22.50 EXP 11/18/06' => 'XLQKX',
    'CALL XILINX INC$22.50 EXP 04/18/09' => 'XLQDX',
    'CALL XILINX INC$25 ADJ EXP 01/20/07' => '',
    'CALL XILINX INC$25 EXP 03/22/08' => 'XLQCE',
    'CALL XILINX INC$25 EXP 04/19/08' => 'XLQDE',
    'CALL XILINX INC$25 EXP 06/21/08' => 'XLQFE',
    'CALL XILINX INC$25 EXP 07/19/08' => 'XLQGE',
    'CALL XILINX INC$25 EXP 10/18/08' => '',
    'CALL XILINX INC$25 EXP 10/21/06' => 'XLQJE',
    'CALL XILINX INC$25 EXP 11/18/06' => 'XLQKE',
    'CALL XILINX INC$25 EXP 12/16/06' => 'XLQLE',
    'CALL XILINX INC$27.50 EXP 03/17/07' => 'XLQCY.x',
    'CALL XILINX INC$27.50 EXP 05/19/07' => 'XLQEY',
    'CALL XILINX INC$27.50 EXP 06/16/07' => 'XLQFY',
    'CALL XILINX INC$27.50 EXP 09/20/08' => 'XLQIY',
    'CALL XILINX INC$27.50 EXP 11/17/07' => 'XLQKY',
    'CALL XILINX INC$30 EXP 09/16/06' => '',
    'CALL XILINX INC$30 EXP 09/22/07' => 'XLQIF',
    'CALL XILINX INC$22.50 EXP 09/19/09' => '',
    'CALL XILINX INC$21 EXP 09/19/09' => '',
    'CALL XILINX INC$23 EXP 10/17/09' => '',
    'CALL XILINX INC$21 EXP 10/17/09' => '',
    'CALL XILINX INC$21 EXP 11/21/09' => '',
    'CALL XILINX INC$24 EXP 11/21/09' => '',
    'CALL XILINX INC$22 EXP 11/21/09' => '',
    'CALL: XILINX INC - XLQ 04/17/2010 27.00 C' => '',
    'CALL: XILINX INC - XLQ 05/22/2010 28.00 C' => '',
    'CALL: XILINX INC - XLNX 08/21/2010 28.00 C' => '',
    'CALL: XILINX INC - XLNX 02/19/2011 29.00 C' => '',
    'CALVERT INCOME FUND A' => 'CFICX',
    'Cisco Systems' => '1',
    'Cortland General' => '1',
    'Dell Computer' => '1',
    'DODGE & COX  INTERNATIONAL STOCK FUND' => 'DODFX',
    'DODGE & COX STOCK FUND' => 'DODGX',
    'Eaton Vance Large-Cap Value A' => 'EHSTX',
    'E Trade Group Inc' => '1',
    'E TRADE BK EXTNDED INS SWEEP DEP ACCT 5.00% 09/01/2018' => '1',
    'E*TRADE RUSSELL 2000 INDEX' => 'ETRUX',
    'E*TRADE S&P 500 INDEX' => 'ETSPX',
#    'FAIRHOLME FUND' => 'FAIRX',  # Temporary
    'FBR SMALL CAP FINANCIAL FUND/A' => 'FBRSX',
    'FORWARD HOOVER SMALL CAP EQUITY' => 'FFSCX',
    'GENTNER COMMUNICATIONS CORP' => '1',
    'GLOBAL CROSSING LTD' => '1',
    'GOOGLE INC' => '1',
#    'Harbor International Instl' => 'HAINX',  # Temporary
    'General Electric Co' => '1',
    'HARRIS INSIGHT SMALL CAP VALUE N' => 'HSVAX',
    'HEALTH CARE FOCUS FUND' => 'SWHFX',
    'Hewlett-Packard' => '1',
    'HENLOPEN FUND' => 'HENLX',
    'Home Depot' => '1',
    'INTEREST ON CREDIT BALANCE' => '1',
    'INTERNET FUND' => 'WWWFX',
    'Intel Corp' => '1',
    'Intl Business Mach Corp' => '1',
    'Invesco Income Fund' => 'FHYPX',
    'ISHARES TR FTSE XNHUA IDX' => 'FXI',
    'JAMES ADVANTAGE SMALL CAP FUND' => 'JASCX',
    'JANUS HIGH YIELD FUND' => 'JAHYX',
    'JANUS MID CAP VALUE - INVESTOR SHARES' => 'JMCVX',
    'JPMORGAN CA MUNI MM E*TRADE' => 'JCEXX',
    'KINETICS INTERNET NEW PARADIGM' => 'WWNPX',
    'LAUDUS ROSENBERG:INTL SMALL CAPITALIZATION/INV' => 'RISIX',
    'Lucent Technologies Inc' => '1',
    'MASTERS SELECT SMALLER COMPANS FUND' => 'MSSFX',
    'MCK' => '1',
    'Microsoft' => '1',
    'OAKMARK INTERNATIONAL FUND' => 'OAKIX',
    'OPPENHEIMER QUEST BAL VALUE A' => 'QVGIX',
    'Oracle Corp' => '1',
    'PASSIVE AGE BASED PORTFOLIO 5-8 - 2937' => '1',
    'PASSIVE AGE BASED PORTFOLIO 9-10 - 2938' => '1',
    'PHOENIX  INSIGHT SMALL CAP VALUE FUND CLASS A' => 'HSVZX',
    'PRINCIPAL SAM CONSERV GROWTH PORT CL B' => '1',
    'PRUDENTIAL JENNISON NATURAL RES C' => '1',
    'ROYCE VALUE PLUS FUND INVESTOR CLASS' => 'RYVPX',
    'RS VALUE FUND' => 'RSVAX',
    'SCH CA MUNI MONEY FD SWEEP SHA' => 'SWCXX',
    'SCHRODER CAPITAL US OPPORTUNITIES FUND/INV' => 'SCUIX',
    'Schwab Instl Select S&P 500' => 'ISLCX',
    'SEC_8b3' => '1',
    'SEQUOIA FUND' => 'SEQUX',
    'SSGA TUCKERMAN ACTIVE REIT' => 'SSREX',
    'SPDR S&P EMERGING ASIA' => 'GMF',
    'S P D R TRUST UNIT SR 1 EXPIRING 01/22/2118' => 'SPY',
    'STRONG ASIA PACIFIC' => 'SASPX',
    'VICTORY DIVERSIFIED STOCK FUND' => 'SRVEX',
    'Starbucks Corp' => '1',
    'Target Retirement 2030 Trust II' => 'VTHRX',
    'T. ROWE PRICE FINANCIAL SERVICES' => 'PRISX',
    'T. ROWE PRICE MID-CAP VALUE' => 'TRMCX',
    'TCW GALILEO VALUE OPP N' => 'TGVNX',
    'TEMPLETON GROWTH FUND CL A' => 'TEPLX',
    'THIRD AVENUE REAL ESTATE VALUE' => 'TAREX',
#    'THIRD AVENUE VALUE FUND' => 'TAVFX',  # Temporary
    'TRANSCANADA PIPE LINE' => 'TRP',
    'US Airways' => '1',
    'Unknown Security 999903016' => '',
    'Unknown Security JEMIZ' => '1',
    'Unidentified Security' => '',
    'Vanguard 500 Index Fund Admiral Shares' => 'VFIAX',
    'Vanguard California Tax-Exempt Money Market Fund' => 'VCTXX',
    'Vanguard Emerging Markets Stock Index' => 'VEMAX', # converted to adm shrs
    'Vanguard Energy Fund Investor Shares' => 'VGENX',
    'VANGUARD EXTENDED MKT FDSTK MKT VIPERS' => 'VXF',
    'Vanguard FTSE All-World ex-US Index Fund Investor Shares' => '',
    'Vanguard High-Yield Corporate Fund Investor Shares' => 'VWEHX',
    'Vanguard Intermediate-Term Bond Index Fund Admiral Shares' => 'VBILX',
    'Vanguard Long-Term Treasury Fund Investor Shares' => 'VUSUX', # all became VUSUX
    'VANGUARD MATERIALS' => 'VAW',
    'Vanguard Mid-Cap Index Fund Investor Shares' => 'VIMAX', # converted to adm
    'Vanguard SP 500 index' => 'VFIAX',  # This was transfered to VFIAX
    'VANGUARD LONG-TERM CORPORATE BOND' => 'VWESX',
    'Vanguard Inflation-Protected Securities Fund Investor Shares' => 'VIPSX',
    'VANGUARD INTERNATIONAL VALUE' => 'VTRIX',
    'Vanguard Pacific Stock Index Fund Investor Shares' => 'VPACX',
    'VANGUARD SHORT-TERM FEDERAL' => 'VSGBX',
    'Vanguard Small-Cap Growth Index Fund' => 'VISGX',
    'Vanguard Small-Cap Value Index Fund' => 'VISVX',
    'Vanguard Tax-Exempt Money Market Fund' => '',
    'VIRTUS INSIGHT SMALL CAP VALUE A' => 'HSVZX',
    'VODAFONE AIRTOUCH PLC SP ADR' => '1',
    'Wal-Mart Stores Inc' => '1',
    'XILINX INC' => '1',
    'Xilinx' => '1',
    'XILINX INC' => '1',
    'XLNX Dec 27.5 Call' => '1',
    'XLNX Dec-06 $25 Call' => '1',
    'XLNX Feb 30 Call' => '1',
    'XLNX Oct 25 Call' => '1',
    'XLNX Sep 30 Call' => '1',
    'XLQ APR 30 Call' => '1',
    'XLQ APR 50 Call' => '1',
    'XLQ AUG $27.50 CALL' => '1',
    'XLQ AUG 15 Put' => '1',
    'XLQ AUG 50 Call (S)' => '1',
    'XLQ DEC $30 CALL' => '1',
    'XLQ DEC $32.50 CALL' => '1',
    'XLQ DEC $35 CALL' => '1',
    'XLQ DEC 25 Call' => '1',
    'XLQ DEC 40 Call (S)' => '1',
    'XLQ DEC-06 $25 CALL' => '1',
    'XLQ JAN 50 Call' => '1',
    'XLQ JUL $27.50 CALL' => '1',
    'XLQ JUL 27 1/2 CALL' => '1',
    'XLQ JUL 32 1/2 CALL' => '1',
    'XLQ JUN $27.50 CALL' => '1',
    'XLQ JUN 30 Call' => '1',
    'XLQ JUN 45 Call' => '1',
    'XLQ JUN 50 Call' => '1',
    'XLQ MAR $27.50 CALL' => '1',
    'XLQ MAR $30 CALL' => '1',
    'XLQ MAR 17 1/2 PUT' => '1',
    'XLQ MAR 50 Call' => '1',
    'XLQ MAY $27.50 CALL' => '1',
    'XLQ MAY $30 CALL' => '1',
    'XLQ NOV $27.50 CALL' => '1',
    'XLQ NOV $32.50 CALL' => '1',
    'XLQ OCT $22.50 CALL' => '1',
    'XLQ OCT 15 Put' => '1',
    'XLQ OCT 25 Call (S)' => '1',
    'XLQ SEP $30 CALL' => '1',
    'XLQ SEP $32.50 CALL' => '1',
    'XLQ SEP 15 Put' => '1',
    'XLQ SEP 30 Call' => '1',
    'XLQ SEP 50 Call (S)' => '1',
    'XLW JUN 60 Call (S)' => '1',
    'XLWEL' => '1',
    'XPEDIOR INC' => '1',
    'Yahoo' => '1',
    'Yahoo ESPP' => '1',
    'Yahoo Option' => '1',
    'Aetna Fixed' => '1',
    'Aetna Variable' => '1',
    'TCI Growth' => '1',
    'Alger Small Cap' => '1',
    'DREYFUS APPRECIATION FUND' => '1',
    'HENNESSY CORNERSTONE GROWTH II' => '1',
    'SCHWAB RETIREMENT ADVANTAGE' => '1',
    );

our %Tickers = (
    'American Funds Growth Fund of Amer R4' => 'RGAEX',
    'Columbia Mid Cap Value Z' => 'NAMAX',
    'Eaton Vance Large-Cap Value I' => 'EILVX',
    'EXCELSIOR VALUE AND RESTRUCTURING FUND' => 'UMBIX',
    'FAIRHOLME FUND' => 'FAIRX',
    'Harbor International Instl' => 'HAINX',
    'IPATH DOW JONES-UBS COMMODITY INDEX TOTAL RETURN ETN' => 'DJP',
    'LOOMIS SAYLES GLOBAL BOND/RETAIL' => 'LSGLX',
    'Nuveen Winslow Large-Cap Growth I' => 'NVLIX',
    'PIMCO Total Return Instl' => 'PTTRX',
    'RIDGEWORTH US GOV SEC ULTRA SHORT BD I' => 'SIGVX',
    'Royce Low Priced Stock Svc' => 'RYVPX',
    'SCHWAB S&P 500 INDEX SEL' => 'SWPPX',
    'SPDR GOLD TRUST GOLD SHARES' => 'GLD',
    'THIRD AVENUE VALUE FUND' => 'TAVFX',
    'T. Rowe Price Instl Large Cap Value' => 'TILCX',
    'UMB SCOUT WORLDWIDE FUND' => 'UMBWX',
    'Vanguard 500 Index Fund Signal Shares' => 'VIFSX',
    'Vanguard California Intermediate-Term Tax-Exempt Fund Investor Shares' => 'VCAIX',
    'Vanguard Convertible Securities Fund' => 'VCVSX',
    'VANGUARD DIVIDEND APPRECIATION ETF' => 'VIG',
    'VANGUARD EMERGING MARKET' => 'VWO',
    'Vanguard Emerging Markets Stock Index Fund Admiral Shares' => 'VEMAX',
    'VANGUARD ENERGY ETF' => 'VDE',
    'Vanguard Extended Market Index Fund Investor Shares' => 'VEXMX',
    'VANGUARD FTSE ETF **PENDING ENLISTMENT* --BEST EFFOR' => 'VSS',
    'Vanguard FTSE All-World ex-US Index Fund Admiral' => 'VFWAX',
    'Vanguard FTSE All-World ex-US Small-Cap Index Fund Investor Shares' => 'VFSVX',
    'VANGUARD GLOBAL EQUITY FUND INVESTOR SHARE' => 'VHGEX',
    'Vanguard GNMA Fund Admiral Shares' => 'VFIJX',
    'Vanguard High-Yield Corporate Fund Admiral Shares' => 'VWEAX',
    'Vanguard Inflation-Protected Securities Fund Admiral Shares' => 'VAIPX',
    'Vanguard Intermediate-Term Investment-Grade Fund Admiral Shares' => 'VFIDX',
    'VANGUARD INTL EQTY INDEXFTSE ALL WORLD EX US ETF' => 'VEU',
    'Vanguard Long-Term Treasury Fund Admiral Shares' => 'VUSUX',
    'VANGUARD MEGA CAP 300 INDEX ETF' => 'MGC',
    'VANGUARD MID CAP ETF' => 'VO',
    'Vanguard Mid-Cap Growth Fund' => 'VMGRX',
    'Vanguard Mid-Cap Index Fund Admiral Shares' => 'VIMAX',
    'Vanguard Prime Money Market Fund' => 'VMMXX',
    'VANGUARD REIT' => 'VNQ',
    'Target Retirement 2030 Trust I' => 'VTHRX',
    'VANGUARD SHORT TERM BOND ETF' => 'BSV',
    'VANGUARD SMALL-CAP VIPERS' => 'VB',
    'VANGUARD TOTAL INTL STOCK INDEX' => 'VGTSX',
    'Victory Inst Diversified Stock' => 'VIDSX',
    'William Blair International Growth N' => 'WBIGX',
    );

# Use a bit vec for Morningstar asset classes.
# Something has to have >25% to be in the category
our $UsStock = 1;
our $IntlStock = 2;
our $Bond = 4;
our $RealAsset = 8;
our $Cash = 16;
our %AssetClass = (
    'ARTKX' => $IntlStock,
    'ARTQX' => $UsStock,
    'AVPAX' => $UsStock,
    'BEGBX' => $Bond,
    'BIOPX' => $UsStock,
    'BRK.B' => $UsStock,
    'BSV' =>   $Bond,
    'BTTRX' => $Bond,
    'CFICX' => $Bond,
    'DJP' => $RealAsset,
    'DODFX' => $IntlStock,
    'DODGX' => $UsStock,
    'EILVX' => $UsStock,
    'ETRUX' => $UsStock,
    'FAIRX' => $IntlStock | $UsStock,
    'FBRSX' => $UsStock,
    'FFSCX' => $UsStock,
    'FXI'   => $IntlStock,
    'GLD' => $RealAsset,
    'GMF'   => $IntlStock,
    'HAINX' => $IntlStock,
    'HSVZX' => $UsStock,
    'ISLCX' => $UsStock,
    'JASCX' => $UsStock,
    'JMCVX' => $UsStock,
    'LSGLX' => $Bond,
    'MGC' => $UsStock,
    'MSSFX' => $UsStock,
    'NAMAX' => $UsStock,
    'NVLIX' => $UsStock,
    'PTTRX' => $Bond,
    'RGAEX' => $UsStock | $IntlStock,
    'RISIX' => $IntlStock,
    'RSVAX' => $UsStock,
    'RYVPX' => $UsStock | $IntlStock,
    'SASPX' => $IntlStock,
    'SCUIX' => $UsStock,
    'SEQUX' => $UsStock,
    'SIGVX' => $Cash,
    'SPY'   => $UsStock,
    'SSREX' => $UsStock,
    'SWHFX' => $UsStock,
    'SWPPX' => $UsStock,
    'TAREX' => $UsStock | $IntlStock,
    'TAVFX' => $UsStock | $IntlStock,
    'TILCX' => $UsStock,
    'TRMCX' => $UsStock,
    'TRP' => $IntlStock,
    'TWCVX' => $UsStock,
    'UMBIX' => $UsStock | $IntlStock,
    'UMBWX' => $IntlStock,
    'VAIPX' => $Bond,
    'VAW'   => $UsStock,
    'VB' => $UsStock,
    'VBILX' => $Bond,
    'VCAIX' => $Bond,
    'VCVSX' => $Bond,
    'VDE' =>   $UsStock,
    'VEIEX' => $IntlStock,
    'VEU' => $IntlStock,
    'VEMAX' => $IntlStock,
    'VEXMX' => $UsStock,
    'VFIDX' => $Bond,
    'VFIAX' => $UsStock,
    'VFIJX' => $Bond,
    'VFSVX' => $IntlStock,
    'VFWAX' => $IntlStock,
    'VFWIX' => $IntlStock,
    'VGENX' => $UsStock | $IntlStock,
    'VGTSX' => $IntlStock,
    'VHGEX' => $UsStock | $IntlStock,
    'VIDSX' => $UsStock,
    'VIFSX' => $UsStock,
    'VIG' =>   $UsStock,
    'VIMAX' => $UsStock,
    'VIMSX' => $UsStock,
    'VIPSX' => $Bond,
    'VISGX' => $UsStock,
    'VISVX' => $UsStock,
    'VMGRX' => $UsStock,
    'VMMXX' => $Cash,
    'VNQ'   => $UsStock,
    'VO' => $UsStock,
    'VPACX' => $IntlStock,
    'VSS'   => $IntlStock,
    'VTHRX' => $IntlStock | $UsStock | $Bond,
    'VUSTX' => $Bond,
    'VUSUX' => $Bond,
    'VWEAX' => $Bond,
    'VWEHX' => $Bond,
    'VWO'   => $IntlStock,
    'VXF'   => $UsStock,
    'WBIGX' => $IntlStock,
    'WWNPX' => $UsStock | $IntlStock,
    );
our %PortfolioAssetClasses = (
    'all' => $UsStock | $IntlStock | $Bond | $RealAsset | $Cash,
    'US' => $UsStock,
    'Intl' => $IntlStock,
    'Bond' => $Bond,
    );

our %Splits = (
    'BTTRX' => {
	'12-16-2005' => 1.0/1.0346,
	'12-15-2006' => 1.0/1.0453,
	'12-13-2008' => 110.79/115.735,
    },
    'FXI' => {
	'7-24-2008' => 91.767239/30.76708,
#	'7-24-2008' => 91.767239,
    },
    );

# Usually this is needed because of a conversion or other asset move
our %TreatAddAsBuy = (
    'VEMAX' => 1,
    'VFIJX' => 1,
    'VFWAX' => 1,
    'VTHRX' => 1,
    'VWEAX' => 1,
    'VAIPX' => 1,
    'VFIDX' => 1,
    'VUSUX' => 1,
    'VIMAX' => 1,
    'LSGLX' => 1,
    'VEU' => 1,
    'VWO' => 1,
    'DJP' => 1,
);

our %TreatRemoveAsSell = (
    'VEU' => 1,
    'VWO' => 1,
    'DJP' => 1,
);

# 12 month yield from morningstar
our $Yield = {
    'BSV' => 1.83,
    'DJP' => 0,
    'GLD' => 0,
    'LSGLX' => 4.10,
    'MGC' => 1.92,
    'SIGVX' => 1.03,
    'VAIPX' => 3.69,
    'VB' => 1.23,
    'VCAIX' => 3.45,
    'VCVSX' => 3.75,
    'VDE' => 1.55,
    'VEMAX' => 2.12,
    'VEU' => 3.16,
    'VFIDX' => 4.12,
    'VFIJX' => 3.21,
    'VFWAX' => 0,
    'VFSVX' => 2.59,
    'VIG' => 2.01,
    'VIMAX' => 1.20,
    'VMMXX' => 0.04,
    'VNQ' => 3.27,
    'VSS' => 2.84,
    'VUSUX' => 2.86,
    'VWEAX' => 6.84,
    'VWO' => 2.12,
    'VO' => 1.20,
};

# I thought Morningstar now supports reinvested dividends, but they don't appear to.
# They used to turn all dividends into reinvested dividends.  Now they turn all dividends into cash dividends.
#

# Use if dividends are all treated as reinvested dividends
# our %Actions = (
#     'Buy' => 'buy',
#     'BuyX' => 'buy',
#     'Cash' => 'skip',
#     'CGLong' => 'cash-div',
#     'CGLongX' => 'cash-div',
#     'CGShort' => 'cash-div',
#     'CGShortX' => 'cash-div',
#     'Div' => 'cash-div',
#     'DivX' => 'cash-div',
#     'MiscExpX' => 'cash-div',
#     'ReinvDiv' => 'div',
#     'ReinvLg' => 'div',
#     'ReinvSh' => 'div',
#     'SellX' => 'sell',
#     'ShrsIn' => 'add',
#     'ShrsOut' => 'remove',
#     'StkSplit' => 'split',
#     'Sell' => 'sell',
#     );

# Use if dividends are properly differentiated: div vs reinv
our %Actions = (
    'Buy' => 'buy',
    'BuyX' => 'buy',
    'Cash' => 'skip',
    'CGLong' => 'div',
    'CGLongX' => 'div',
    'CGShort' => 'div',
    'CGShortX' => 'div',
    'Div' => 'div',
    'DivX' => 'div',
    'MiscExpX' => 'div',
    'ReinvDiv' => 'reinv',
    'ReinvLg' => 'reinv',
    'ReinvSh' => 'reinv',
    'SellX' => 'sell',
    'ShrsIn' => 'add',
    'ShrsOut' => 'remove',
    'StkSplit' => 'split',
    'Sell' => 'sell',
    );

# Use if all dividends are treated as cash dividends.
# See Comment next to where this is used.
# our %Actions = (
#     'Buy' => 'buy',
#     'BuyX' => 'buy',
#     'Cash' => 'skip',
#     'CGLong' => 'div',
#     'CGLongX' => 'div',
#     'CGShort' => 'div',
#     'CGShortX' => 'div',
#     'Div' => 'div',
#     'DivX' => 'div',
#     'MiscExpX' => 'div',
#     'ReinvDiv' => 'reinv-div',
#     'ReinvLg' => 'reinv-div',
#     'ReinvSh' => 'reinv-div',
#     'SellX' => 'sell',
#     'ShrsIn' => 'add',
#     'ShrsOut' => 'remove',
#     'StkSplit' => 'split',
#     'Sell' => 'sell',
#     );

our $OutDir = 'out';

# Less than this number of shares is considered a zero balance
my $gZero = 2.0;

# --------------------------------------------------------
# The script
# --------------------------------------------------------

# Data structures are passed into the function.  No global data is
# modified directly within the functions.

# Contains all the data, organized by ticker
# $rhQif->{$ticker}->[$i] is the data for row i for that ticker
# $rhQif->{$ticker}->[$i]->{'Shares'} is the value in the Shares col
my $rhQif = {};

# $rhMStarShares->{$name} is the total shares for that asset
# as computed from all the transactions in the QIF files.
my $rhMStarShares = {};

# $rhQPortfolioShares->{$name} is the total shares for that asset read
# from the $quickenPortfolio.
my $rhQPortfolioShares = {};

# An array of names in the order they came from the portfolio
my $raQPortfolioSecurityNames = [];

# Stores precent allocations and tickers associated with asset allocation categories.
# $rhAssetAllocations->{$portfolio}->{'values'}->{$category} = $allocation;
# $rhAssetAllocations->{$portfolio}->{'categories'}->{$ticker} = $category;
# $rhAssetAllocations->{$portfolio}->{'tickers'}->{$category}->[0] = $ticker;
my $rhAssetAllocations = {};

# $rhPrices->{$ticker} = $price;
my $rhPrices = {};

# $rhPerAcctShares->{$ticker}->{$acct} = $shares
my $rhPerAcctShares = {};

# New: Ticker objects, indexed by symbol
my $rhTickers = {};

# New: Portfolio objects, indexed by portfolio name
my $rhPortfolios = {};

&main(
    'quicken-portfolio.csv',
    'quicken',
    $rhQif,
    $rhMStarShares,
    $rhQPortfolioShares,
    $raQPortfolioSecurityNames,
    $rhPrices,
    'asset-allocation-',
    $rhAssetAllocations,
    $rhPerAcctShares,
    $rhTickers,
    $rhPortfolios,
    );
exit 0;

# --------------------------------------------------------
# Subroutines
# --------------------------------------------------------

sub main {
    my $quickenPortfolio = shift;
    my $qifDir = shift;
    my $rhQif = shift;
    my $rhMStarShares = shift;
    my $rhQPortfolioShares = shift;
    my $raQPortfolioSecurityNames = shift;
    my $rhPrices = shift;
    my $assetAllocationPrefix = shift;
    my $rhAssetAllocations = shift;
    my $rhPerAcctShares = shift;
    my $rhTickers = shift;
    my $rhPortfolios = shift;
    
    print "*************************************************************\n";
    print "Reading portfolio from $quickenPortfolio\n";
    &Read_Quicken_Portfolio($quickenPortfolio, $rhQPortfolioShares,
			    $raQPortfolioSecurityNames, $rhPrices);

    print "*************************************************************\n";
    print "Reading transactions from QIF files\n";
    &Read_Qif_Files( $rhQif, $qifDir );
    &Process_Qif_Data( $rhQif, $rhMStarShares, $rhPerAcctShares );

    print "*************************************************************\n";
    print "Writing files to upload to Morningstar\n";
    -d $OutDir || mkdir $OutDir;
    &Write_MStar_Files_Per_Portfolio( $rhQif, \%PortfolioDefs );

    # Compare list of files found to those in portfolios
    # &Write_Portfolio_Comparison();
    
    print "*************************************************************\n";
    print "Sanity check QIF transactions to overall portfolio.\n";
    &Write_Comparison( $rhMStarShares, $rhQPortfolioShares, $raQPortfolioSecurityNames);

    # Can get prices from the portfolio, which is much faster.
    # &Read_Prices_From_Qif_Files($rhPrices, $qifDir);
    # &Make_Sure_Prices_Are_Uptodate($rhPrices, $raQPortfolioSecurityNames);

    print "*************************************************************\n";
    print "Read asset allocations.\n";
    &Create_Portfolios(\%PortfolioDefs, $rhPortfolios);
    &Read_Asset_Allocation_Csv_Per_Portfolio( $assetAllocationPrefix,
					      $rhPortfolios, $rhTickers );
    &Write_Asset_Allocation_Csv_Per_Portfolio( $rhPortfolios, $rhAssetAllocations,
					       $rhPrices, $rhPerAcctShares,
					       $raQPortfolioSecurityNames);
}

# --------------------------------------------------------

sub Read_Quicken_Portfolio {
    my $fname = shift;
    my $rhQPortfolioShares = shift;
    my $raQPortfolioSecurityNames = shift;
    my $rhPrices = shift;
	
    my $csv = Text::CSV_XS->new ({ binary => 1, eol => $/ });
    open my $io, "<", $fname or die "$fname: $!";

    # Skip to data
    while (my $row = $csv->getline ($io)) {
	last if ( $row->[1] eq 'Security' );
    }
    # Skip extra blank row
    $csv->getline ($io);

    # handle the transactions
    while (my $row = $csv->getline ($io)) {
	my $name = $row->[1];
	my $shares = $row->[2];
	$shares =~ tr/,\r//d;
	my $price = $row->[3];
	$price =~ tr/,\r//d;
	next if $shares eq "";
	push @{ $raQPortfolioSecurityNames }, $name;
	$rhQPortfolioShares->{$name} = $shares;
	if ( defined $Tickers{$name} ) {
	    $rhPrices->{$Tickers{$name}} = $price;
	}
# 	printf( "Found %f shares of \"%s\" at %.2f\n",
# 		$shares, $name, $price );
    }
    close $io;
}

sub Read_Qif_Files {
    my $rhQif = shift;
    my $dir = shift;

    # Just reduces clutter on error messages if an action
    # hasn't been seen before.
    my %actionsSeen;

    opendir(DIR, $dir) || die "can't opendir $dir: $!";
    foreach my $file (readdir (DIR) ) {
	next unless $file =~ /^(.*)\.qif$/i;
	my $base = $1;
	print "Reading File: ", $file, ":\n";
	&Read_Qif($rhQif, $dir, $base, \%actionsSeen);
    }
    closedir DIR;
}

sub Read_Qif {
    my $rhQif = shift;
    my $dirname = shift;
    my $basename = shift;
    my $rhActionsSeen = shift;

    my $fname = "$dirname/$basename.qif";

    my $qif = Finance::QIF->new( file => $fname );

    # Just print out security names
#     my %namesSeen;
#     while ( my $record = $qif->next ) {
# 	if ( $record->{'header'} eq 'Type:Invst' ) {
# 	    if ( defined($record->{$security}) 
# 		 && !defined($namesSeen{$record->{$security}}) ) {
# 		$namesSeen{$record->{$security}}++;
# 		print $record->{$security}, "\n";
# 	    }
# 	}
#     }

    my %namesSeen;
    while ( my $record = $qif->next ) {
 	if ( $record->{'header'} eq 'Type:Invst' ) {
 	    if ( defined($record->{$security}) ) {

		#
# 		print "Record: \n";
# 		foreach my $k ( sort keys %{ $record } ) {
# 		    print "  $k = $record->{$k}\n";
# 		}

		my $name = $record->{$security};
		$name =~ tr/\r//d;
#		print "Security \"$name\"\n";
		next if ( defined($Skip{$name}) );
		if ( ! defined($Tickers{$name}) ) {
		    if ( !defined($namesSeen{$name}) ) {
			$namesSeen{$name}++;
			print "*** Add the following to \%Tickers or \%Skip\n";
			print "    '", $name, "' => '',\n";
			
		    }
		    next;
		}
		my $ticker = $Tickers{$name};
		if ( ! defined($AssetClass{$ticker}) ) {
		    if ( !defined($namesSeen{$name}) ) {
			$namesSeen{$name}++;
			print "*** Add the following to \%AssetClass\n";
			print "    '", $ticker, "' => \$IntlStock | \$UsStock | \$Bond,\n";
		    }
		}
		$record->{'Ticker'} = $ticker;
		$record->{$security} = $name;
		my $date = &Convert_Qif_Date($record->{'date'});
		$record->{'date'} = $date;
		$record->{'file'} = $basename;

		# Copy the fields to fields keyed by keys that morningstar understands
		foreach my $k ( keys %{ $record } ) {
		    if ( defined $ToMstar{$k} ) {
			$record->{$ToMstar{$k}} = $record->{$k};
		    }
		}

		$record->{'Comm'} = 0 if ( !defined $record->{'Comm'} );

		my $comm = $record->{'Comm'};
		$comm =~ tr/,//d;
		$comm =~ s/\s+$//;
		$record->{'Comm'} = $comm;

		my $price = $record->{'Price'};

		# Use previous price if price undefined
		if (! defined $record->{'Price'} && defined $rhQif->{$ticker}) {
		    my $lastRow = scalar @{$rhQif->{$ticker}} - 1;
		    $price = $rhQif->{$ticker}->[$lastRow]->{'Price'};
		}

		$price =~ tr/,//d;
		$price =~ s/\s+$//;
		$record->{'Price'} = $price;

		if ( defined $record->{'Amount'} ) {
		    my $amount = $record->{'Amount'};
		    $amount =~ tr/,//d;
		    $amount =~ s/\s+$//;
		    $record->{'Amount'} = $amount;
		}

		if ( defined $record->{$Shares} ) {
		    my $shares = $record->{$Shares};
		    $shares =~ tr/,//d;
		    $shares =~ s/\s+$//;
		    $record->{$Shares} = $shares;
		} else {
		    # Calculate shares if unknown
		    if ( defined $record->{'Amount'}
			 && defined $record->{'Price'}
			 && defined $record->{'Comm'} )
		    {
			$record->{$Shares} = ($record->{'Amount'} - $comm) / $price;
		    }
		}

		# There are only 5 actions in morningstar: buy, sell, split, div, reinv
		# We define extra psuedo actions: skip, add
		# OLD comment:
		#    There are only 4 actions in morningstar: buy, sell, split, div
		#    We define extra psuedo actions: skip, cash-div
		# All the 
		my $action = $record->{'Action'};
		$action =~ tr/\r//d;
		if ( defined($Actions{$action}) ) {
		    # $record->{'Action'} = $action = $Actions{$action};
		    $action = $Actions{$action};
		} else {
		    print "Action \"$action\" unknown\n";
		}
		if ( $action eq 'buy' ) {
		    $record->{'Action'} = $action;
		} elsif ( $action eq 'add' ) {
		    if ( defined $TreatAddAsBuy{$ticker} ) {
			printf( "Treating add as buy for \"%s\" on %s\n",
				$ticker, $date);
			$record->{'Action'} = 'buy';
		    } else {
			next;
		    }
		} elsif ( $action eq 'remove' ) {
		    if ( defined $TreatRemoveAsSell{$ticker} ) {
			printf( "Treating remove as sell for \"%s\" on %s\n",
				$ticker, $date);
			$record->{'Action'} = 'sell';
		    } else {
			next;
		    }
		} elsif ( $action eq 'sell' ) {
		    $record->{'Action'} = $action;
		} elsif ( $action eq 'split' ) {
		    if (defined $rhQif->{$ticker}) {
			my $lastRow = scalar @{$rhQif->{$ticker}} - 1;
			$record->{'Price'} =
			    $rhQif->{$ticker}->[$lastRow]->{'Price'};
		    }
		    $record->{'Amount'} = 0;
		    $record->{'Action'} = $action;
		    if ( defined( $Splits{$ticker}{$date} ) ) {
			$record->{$Shares} = $Splits{$ticker}{$date};
		    } else {
			printf( "WARNING: No split info for \"%s\" on %s\n",
			       $ticker, $date);
		    }

		} elsif ( $action eq 'div' ) {
		    $record->{'Action'} = $action;
		} elsif ( $action eq 'reinv' ) {
		    $record->{'Action'} = $action;
  		} elsif ( $action eq 'skip' ) {
  		    next;
		    
 		} elsif ( $action eq 'cash-div' ) {
 		    # This is the tricky one
 		    # Record a cash dividend as a
 		    # reinvDiv followed by a sale
 		    my $shares = $record->{$Shares};

 		    my $rhCopy = {};
 		    foreach my $k ( keys %{ $record } ) {
 			$rhCopy->{$k} = $record->{$k};
 		    }

 		    $rhCopy->{'Action'} = 'div';
 		    $record->{'Action'} = 'sell';
 		    push @{$rhQif->{$ticker}}, $rhCopy;

 		} elsif ( $action eq 'reinv-div' ) {
 		    # This is the tricky one
 		    # Record a reinvest dividend as a
 		    # reinvDiv followed by a buy
 		    my $shares = $record->{$Shares};
 		    my $price;

 		    my $rhCopy = {};
 		    foreach my $k ( keys %{ $record } ) {
 			$rhCopy->{$k} = $record->{$k};
 		    }

 		    $rhCopy->{'Action'} = 'div';
 		    $record->{'Action'} = 'buy';
 		    push @{$rhQif->{$ticker}}, $rhCopy;
		} else {
		    if ( !defined($rhActionsSeen->{$action}) ) {
			$rhActionsSeen->{$action}++;
			print "'", $action, "' => '',\n";
		    }
		}

# 		print "Processed:\n";
# 		foreach my $k ( sort keys %{ $record } ) {
# 		    print "  $k = $record->{$k}\n";
# 		}

		push @{$rhQif->{$ticker}}, $record;
 	    }

# Note that the parsing of prices in Finances::QIF is broken, so this doesn't
# work.  Had to write it myself, which was pretty easy.	    
#  	} elsif ( $record->{'header'} eq 'Type:Prices' ) {
# 	    if ( exists( $record->{$prices} ) && exists( $record->{$symbol} ) ) {
# 		my $ticker = $record->{$security};

# 		foreach my $key ( keys %{$record} ) {
# 		    next
# 			if ( $key eq "header"
# 			     || $key eq "splits"
# 			     || $key eq "budget"
# 			     || $key eq "prices" );
# 		    print( "     ", $key, ": ", $record->{$key}, "\n" );
# 		}
# 		foreach my $price ( @{ $record->{$prices} } ) {
# 		    foreach my $k2 ( keys %{$price} ) {
# 			print( "     ", $k2, ": ", $price->{$k2}, "\n" );
# 		    }
# 		    my $date = &Convert_Qif_Date($price->{"date"});
# 		    my $price = 0.0 + $price->{"close"};
# 		    next if $date eq "";
# 		    print "\"", join( "\", \"", $ticker, $date, $price), "\"\n";
# 		    # overwrite the value, since we need only the last price
# 		    $rhPrices->{$ticker}->{'price'} = $price;
# 		    $rhPrices->{$ticker}->{'date'} = $date;
# 		}
# 	    }
	}
    }
}

sub Convert_Qif_Date {
    my $date = shift;
    $date =~ tr/\"\r\n//d;
    $date =~ s/\s*(\d+)\/\s*(\d+)'1(\d)/$1-$2-201$3/;
    $date =~ s/\s*(\d+)\/\s*(\d+)' (\d)/$1-$2-200$3/;
    $date =~ s/\s*(\d+)\/\s*(\d+)\/(\d+)/$1-$2-19$3/;
    return $date;
}

sub Process_Qif_Data {
    my $rhQif = shift;
    my $rhMStarShares = shift;
    my $rhPerAcctShares = shift;
    
    foreach my $ticker ( keys %{ $rhQif } ) {
	next if $ticker eq '';
	&Sort_Transactions( $rhQif, $ticker );

	# As of 4/28/2012, Morningstar appears to work fine with multiple
	# transactions on the same date.
	# &Combine_Transactions( $rhQif->{$ticker} );

	&Prune_Transactions( $rhQif->{$ticker}, $rhMStarShares, $rhPerAcctShares );
    }
}


sub Write_MStar_Files_Per_Portfolio {
    my $rhQif = shift;
    my $rhPortfolioDefs = shift;

    foreach my $portfolio ( keys %{ $rhPortfolioDefs } ) {
	my %rhPortfolio;
	foreach my $f ( @{ $PortfolioDefs{$portfolio} } ) {
	    $rhPortfolio{$f}++;
	}
	foreach my $asset_class ( keys %PortfolioAssetClasses ) {
	    # print "Portfolio: $portfolio, Asset Class $asset_class\n";
	    &Write_Mstar( $rhQif,
			  \@MstarHeaders,
			  $portfolio, \%rhPortfolio, $asset_class,
			  $PortfolioAssetClasses{$asset_class} );
	}
    }
}


sub Read_Prices_From_Qif_Files {
    my $rhPrices = shift;
    my $dir = shift;

    opendir(DIR, $dir) || die "can't opendir $dir: $!";
    foreach my $file (readdir (DIR) ) {
	next unless $file =~ /^(.*)\.qif$/i;
	my $base = $1;
	print "Reading File: ", $file, ":\n";
	&Read_Prices_From_A_Qif($rhPrices, $dir, $base);
    }
    closedir DIR;
}

sub Read_Prices_From_A_Qif() {
    my $rhPrices = shift;
    my $dirname = shift;
    my $basename = shift;

    my $filename = "$dirname/$basename.qif";

    open(my $fh, "<", $filename) or die "cannot open $filename: $!";

    while ( <$fh> ) {
#	print $_;
	if ( /^!Type:Prices$/ ) {
	    my $next_line = <$fh>;
	    if ( defined $next_line ) {
		$next_line =~ tr/\"\r\n//d;
		my ($ticker, $price, $date) = split(/,/, $next_line);
		$date = &Convert_Qif_Date($date);
#		print "\"", join( "\", \"", $ticker, $date, $price), "\"\n";
		$rhPrices->{$ticker}->{'price'} = $price;
		$rhPrices->{$ticker}->{'date'} = $date;
	    }
	}
    }
}
    
# Compares portfolio file with data read from qif files as a sanity check.
sub Make_Sure_Prices_Are_Uptodate {
    my $rhPrices = shift;
    my $raQPortfolioSecurityNames = shift;

    my @today = (localtime)[5,4,3];
    $today[0] += 1900;
    $today[1]++;

    foreach my $name (@{ $raQPortfolioSecurityNames }) {
	next if ( defined $Skip{$name} );
	next unless ( defined($Tickers{$name}) );
	my $ticker = $Tickers{$name};
	if ( defined $rhPrices->{$ticker}->{'date'} ) {
	    my $price_date = $rhPrices->{$ticker}->{'date'};
	    my ($mm,$dd,$yyyy) = ($price_date =~ /(\d+)-(\d+)-(\d+)/);
	    my @date_array = ($yyyy,$mm,$dd);
	    my $days_old = &Delta_Days(@date_array, @today);
	    printf( "Price %.2f for %s is %d days old\n", $rhPrices->{$ticker}->{'price'},
		    $ticker, $days_old );
	    if ( $days_old > 2 ) {
		printf( "OUT OF DATE: Price %.2f for %s is %d days old\n",
			$rhPrices->{$ticker}->{'price'},
			$ticker, $days_old);
	    }
	} else {
	    printf( "No Price information for %s\n", $ticker );
	}
    }
}

sub Create_Portfolios {
    my $rhPortfolioDefs = shift;
    my $rhPortfolios = shift;

    foreach my $portfolioName ( keys %{ $rhPortfolioDefs } ) {
	$rhPortfolios->{$portfolioName} = new Portfolio($portfolioName);
    }
}

sub Read_Asset_Allocation_Csv_Per_Portfolio {
    my $assetAllocationPrefix = shift;
    my $rhPortfolios = shift;
    my $rhTickers = shift;

    foreach my $portfolioName ( keys %{ $rhPortfolios } ) {
	my $portfolio = $rhPortfolios->{$portfolioName};
	my $assetAllocation = new AssetAllocation();
	$portfolio->Set_Asset_Allocation($assetAllocation);
 	$assetAllocation->Read_From_Csv(
	    $assetAllocationPrefix . $portfolioName . ".csv", $rhTickers);
    }
}

# Compares portfolio file with data read from qif files as a sanity check.
sub Write_Comparison {
    my $rhMStarShares = shift;
    my $rhQPortfolioShares = shift;
    my $raQPortfolioSecurityNames = shift;
    
    my $width = 5;
    foreach my $name (@{ $raQPortfolioSecurityNames }) {
	if (length $name > $width) {
	    $width = length $name;
	}
    }
    
    printf("| %${width}s | %10s | %10s |    %10s    |\n", 'NAME', 'QUICKEN',
	   'MORNINGSTAR', 'DIFFERENCE');
    foreach my $name (@{ $raQPortfolioSecurityNames }) {
	printf "| %${width}s | ", $name;
	if (! defined $rhMStarShares->{$name}) {
	    if ( defined $Skip{$name} ) {
		printf("Skip\n");
	    } else {
		printf("WARNING: No QIF transaction data for %f shares in Quicken Portfolio\n",
		       $rhQPortfolioShares->{$name}, $name );
	    }
	} elsif ( abs($rhQPortfolioShares->{$name} - $rhMStarShares->{$name}) > $gZero ) {
	    printf(" %10.3f | %10.3f | ** %10.3f ** |\n",
		   $rhQPortfolioShares->{$name}, $rhMStarShares->{$name},
		   $rhQPortfolioShares->{$name} - $rhMStarShares->{$name} );
	} else {
	    printf(" %10.3f | %10.3f |    %10.3f    |\n",
		   $rhQPortfolioShares->{$name}, $rhMStarShares->{$name},
		   $rhQPortfolioShares->{$name} - $rhMStarShares->{$name} );
	}
    }
}

sub Write_Mstar {
    # Array of rows, each row is a hash ref with keys given by colHeaders
    my $rhQif = shift;         # Array of rows
    my $raColHeaders = shift;  # Column Names
    my $portfolioName = shift; # Portfolio Name
    my $rhPortfolio = shift;   # Ref to hash of filenames in portfolio
    my $assetClasses = shift;  # Asset categories label
    my $_mask = shift;         # Bit mask of asset categories

    my $fname = $OutDir . '/' .
	$portfolioName . '-' . $assetClasses . $time{'-yyyy-mm-dd'} . '.csv';
#     while ( -e $fname ) {
# 	$fname = $_fname . $time{'-yyyy-mm-dd-hhmmss'} . '.csv';
#     }
    open my $io, ">", $fname or die "$fname: $!";
    my $csv = Text::CSV_XS->new;

    print "  Writing $fname\n";

    if ($csv->combine(@{$raColHeaders})) {
	my $string = $csv->string;
	print $io $string, "\n";
    } else {
	my $err = $csv->error_input;
	print "combine () failed on argument: ", $err, "\n";
    }
    
    foreach my $ticker ( sort keys %{ $rhQif } ) {
	next if $ticker eq '';
	next unless $AssetClass{$ticker} & $_mask;
	&Write_Mstar_Ticker( $rhQif->{$ticker}, \@MstarHeaders, $io, $csv,
			     $rhPortfolio);
    }
    close $io;
}

sub Sort_Transactions {
    # Array of rows, each row is a hash ref
    my $rhQif = shift;    # Entire data structure
    my $ticker = shift;    # Entire data structure

    # Array of rows, each row is a hash ref
    my $raData = $rhQif->{$ticker};    # Array of rows

#     my $csv = Text::CSV_XS->new;
#     print "Before Sorting: ticker $ticker\n";
#     &Write_Mstar_Ticker( $rhQif->{$ticker}, \@MstarHeaders, \*STDOUT, $csv, undef);

    # Convert dates into days since year 2000
    my $numRows = scalar @{$raData} - 1;
    foreach my $r ( 0 .. $numRows ) {
	$raData->[$r]->{'age'} = &Date_To_Days_Since_2000($raData->[$r]->{'Date'});
# 	print $raData->[$r]->{'age'}, "\n";
    }z

    $rhQif->{$ticker} = [ sort { $a->{'age'} <=> $b->{'age'} } @{$raData} ];

#     print "After Sorting: ticker $ticker\n";
#     &Write_Mstar_Ticker( $rhQif->{$ticker}, \@MstarHeaders, \*STDOUT, $csv, undef);
}

sub Date_To_Days_Since_2000 {
    my $date = shift;
    my ($mm,$dd,$yyyy) = ($date =~ /(\d+)-(\d+)-(\d+)/);

   my %DaysPerMonth = (
    '1' => 31,
    '2' => 28, # will need leap year correction
    '3' => 31,
    '4' => 30,
    '5' => 31,
    '6' => 30,
    '7' => 31,
    '8' => 31,
    '9' => 30,
    '10' => 31,
    '11' => 30,
    '12' => 31,
    );

 #   print $date, "-> mm = $mm, dd = $dd, yyyy = $yyyy  ==> ";
    my $age = 0;
    foreach my $y ( 2000 .. $yyyy ) {
	$age += 365;
	$age++ if ( Is_Leap($y) );
    }
    foreach my $m ( 1 .. $mm ) {
	$age += $DaysPerMonth{$m};
    }
    $age += $dd;
    return $age;
}

sub Is_Leap {
    my $y = shift;    # year
    return 0 if ( $y % 4 != 0 ); # Leap years are divisible by 4
    return 1 if ( $y % 400 == 0 ); # Any year divisible by 400 is a leap year
    return 0 if ( $y % 100 == 0 ); # Divisible by 100 (but not 400) isn't a leap year
    return 1;
}

sub Combine_Transactions {
    # Array of rows, each row is a hash ref
    my $raData = shift;    # Array of rows

    my $r = 1;

    # Combine transactions for the same date, morningstar doesn't like those.
    #
    # Note that this algorithm changes the number of rows
    # so we can't precompute it.
    while ( $r < scalar @{$raData} ) {
#	print "Row $r\n";
	my $action = $raData->[$r]->{'Action'};

	my $date = $raData->[$r]->{'Date'};

	# Algorithm assumes an invariant that previous rows are already
	# compressed.  So, need go back only until the first matching row.
	my $prev = $r - 1;
	while ( $prev >= 0 ) {
#	    print "  Prev $prev\n";

	    # if our action is div, look for another div to combine with.
	    last if ( $date eq $raData->[$prev]->{'Date'} &&
		      $action eq $raData->[$prev]->{'Action'} );
	    $prev--;
	}

	# Either we found a match or $prev = -1;
	if ( $prev >= 0 ) {
	    # At this point, $prev is a transaction on the same date.
 	    print "Combining action $action for date $date: \n";

 	    print "  Shares: ", $raData->[$prev]->{$Shares}, " + ", $raData->[$r]->{$Shares}, " ==> ";
	    $raData->[$prev]->{$Shares} += $raData->[$r]->{$Shares};
 	    print $raData->[$prev]->{$Shares}, " shares\n";

 	    print "  Amount: ", $raData->[$prev]->{'Amount'}, " + ", $raData->[$r]->{'Amount'}, " ==> ";
	    $raData->[$prev]->{'Amount'} += $raData->[$r]->{'Amount'};
 	    print $raData->[$prev]->{'Amount'}, " Amount\n";
	    
 	    print "  Comm: ", $raData->[$prev]->{'Comm'}, " + ", $raData->[$r]->{'Comm'}, " ==> ";
	    $raData->[$prev]->{'Comm'} += $raData->[$r]->{'Comm'};
 	    print $raData->[$prev]->{'Comm'}, " Comm\n";
	    
 	    print "  Price: ", $raData->[$prev]->{'Price'}, ", ", $raData->[$r]->{'Price'}, " ==> ";
	    if ( $raData->[$prev]->{$Shares} != 0 ) {
		$raData->[$prev]->{'Price'} = ($raData->[$prev]->{'Amount'} - $raData->[$prev]->{'Comm'}) / $raData->[$prev]->{$Shares};
	    }
 	    print $raData->[$prev]->{'Price'}, " Price\n";

	    splice( @{$raData}, $r, 1 );
	    # Don't need to advance $r, since we removed that element
	} else {
	    $r++;
# 	    printf("  No matchin prev, date \"%s\", action \"%s\"\n",
# 		   $date, $action) ;
	}
    }
}

sub Prune_Transactions {
    # Array of rows, each row is a hash ref
    my $raData = shift;    # Array of rows
    my $rhMStarShares = shift;
    my $rhPerAcctShares = shift;

    my $r = 1;
    # Compute transactions running total
    #
    my $total_shares = 0;
    my $numRows = scalar @{$raData} - 1;
    my $name = $raData->[$numRows]->{'Name'};
    my $zero_balance_row = 0;
    foreach my $r ( 0 .. $numRows ) {
	# Double check on share total
	my $action = $raData->[$r]->{'Action'};
	my $shares = $raData->[$r]->{$Shares};
	my $acct = $raData->[$r]->{'file'};
	my $ticker = $raData->[$r]->{'Ticker'};

# 	if ( $name eq 'CALVERT INCOME FUND A' ) {
# 	    printf("WARNING: Quicken Shares %f, MStar shares %f for \"%s\"\n",
# 		   $rhQPortfolioShares->{$name}, $total_shares, $name );
# 	}
#  	if ( $name eq 'FAIRHOLME FUND' ) {
#  	    printf("%s: Quicken Shares %f, MStar shares %f for \"%s\"\n",
#  		   $raData->[$r]->{'Date'}, $rhQPortfolioShares->{$name}, $total_shares, $name );
#  	}

	if ( $action eq 'buy' ) {
	    $total_shares += $shares;
	    $rhPerAcctShares->{$ticker}->{$acct} += $shares
	} elsif ( $action eq 'sell' ) {
	    $total_shares -= $shares;
	    $rhPerAcctShares->{$ticker}->{$acct} -= $shares
	} elsif ( $action eq 'split' ) {
	    $total_shares *= $shares;
	    $rhPerAcctShares->{$ticker}->{$acct} *= $shares
	} elsif ( $action eq 'reinv' ) {
	    $total_shares += $shares;
	    $rhPerAcctShares->{$ticker}->{$acct} += $shares
	} elsif ( $action eq 'div' ) {
	    # No change to share balance
	} else {
	    print "Warning: Bogus action \"$action\"\n";
	}
	$raData->[$r]->{'Running'} = $total_shares;

	# Will point to the last row with a zero balance
	$zero_balance_row = $r if ( $total_shares < $gZero );
    }
    $rhMStarShares->{$name} = $total_shares;
#    print $total_shares, "\n";
#     if ( $rhMStarShares->{$name} < $gZero ) {
# 	printf("WARNING: Only %3f Mstar shares for \"%s\"\n",
# 	       $rhMStarShares->{$name}, $name );
#     }
    
    my $csv = Text::CSV_XS->new;
#     print "With Running Total: \n";
#     &Write_Mstar_Ticker( $raData, \@MstarHeaders, \*STDOUT, $csv, undef);

    # Remove transactions when the running total is < 2 shares
    #
    return unless $zero_balance_row;
#    print "Removing up to row $zero_balance_row: \n";
    splice( @{$raData}, 0, $zero_balance_row+1 );
#    print "After Remove Total: \n";
#    &Write_Mstar_Ticker( $raData, \@MstarHeaders, \*STDOUT, $csv, undef);
}

sub Write_Mstar_Ticker {
    # Array of rows, each row is a hash ref with keys given by colHeaders
    my $raData = shift;    # Array of rows
    my $raColHeaders = shift;
    my $io = shift;
    my $csv = shift;
    my $rhPortfolio = shift;  

    my $printed = 0;
    
    my $numRows = scalar @{$raData} - 1;
    my $numCols = scalar @{$raColHeaders}-1;
    foreach my $r ( 0 .. $numRows ) {
	my @row;
#	print "Row $r\n";

	# A ticker can be in multiple files, so the check must be row at a time
	next unless defined $rhPortfolio->{ $raData->[$r]->{'file'} };
# 	if (not $printed) {
# 	    print "    ", $raData->[$r]->{'Ticker'}, "\n";
# 	    $printed++;
# 	}
	
	my $unknown = 0;
	foreach my $c ( 0 .. $numCols ) {
#	    print "Col $c, \"$raColHeaders->[$c]\"";
	    my $val = 'unknown';
	    if ( defined($raData->[$r]->{$raColHeaders->[$c]}) ) {
		$val = $raData->[$r]->{$raColHeaders->[$c]};
		$val =~ tr/\r//d;
#		print ", \"$val\"";
	    } else {
		$unknown = 1;
	    }
	    push @row, $val;
#	    print "\n";
	}
	if ($csv->combine (@row)) {
	    my $string = $csv->string;
	    print $io $string, "\n";
	    if ($unknown) {
		print "WARNING: Unknown value in \"$string\"\n";
	    }
	} else {
	    my $err = $csv->error_input;
	    print "combine () failed on argument: ", $err, "\n";
	}
    }
}

sub Write_Asset_Allocation_Csv_Per_Portfolio {
    my $rhPortfolioDefs = shift;
    my $rhAssetAllocations = shift;
    my $rhPrices = shift;
    my $rhPerAcctShares = shift;
    my $raQPortfolioSecurityNames = shift;

    foreach my $portfolio ( keys %{ $rhPortfolioDefs } ) {
	if (defined $rhAssetAllocations->{$portfolio}) {
	    &Write_Asset_Allocation_Csv(
		 $portfolio, 
		 $rhPortfolioDefs,
		 $rhAssetAllocations,
		 $rhPrices,
		 $rhPerAcctShares,
		 $raQPortfolioSecurityNames);
	}
    }
}

sub Write_Asset_Allocation_Csv {
    my $portfolio = shift;
    my $rhPortfolioDefs = shift;
    my $rhAssetAllocations = shift;
    my $rhPrices = shift;
    my $rhPerAcctShares = shift;
    my $raQPortfolioSecurityNames = shift;

    my $fname = $OutDir . '/' .
	$portfolio . $time{'-yyyy-mm-dd'} . '.csv';

    open my $io, ">", $fname or die "$fname: $!";
    my $csv = Text::CSV_XS->new;

    print "  Writing $fname\n";

    &Write_Category_Lines(
	$portfolio,
	$rhPortfolioDefs,
	$rhAssetAllocations,
	$rhPrices,
	$rhPerAcctShares,
	$raQPortfolioSecurityNames,
	$io,
	$csv);

    print $io "\n";
    
    &Write_Ticker_Lines(
	$portfolio,
	$rhPortfolioDefs,
	$rhAssetAllocations,
	$rhPrices,
	$rhPerAcctShares,
	$raQPortfolioSecurityNames,
	$io,
	$csv);
    
    close $io;
}

sub Write_Category_Lines {
    my $portfolio = shift;
    my $rhPortfolioDefs = shift;
    my $rhAssetAllocations = shift;
    my $rhPrices = shift;
    my $rhPerAcctShares = shift;
    my $raQPortfolioSecurityNames = shift;
    my $io = shift;
    my $csv = shift;

    my $kCategory = 'Category';
    my $kAllocTickers = 'Alloc Tickers';
    my $kOwnedTickers = 'Owned Tickers';
    my $kValue = 'Value';
    my $kAllocation = 'Allocation';
    my $kCurrentWeight = 'Current Weight';
    my $kDifference = 'Difference';
    my $kDiffPercent = 'Diff %';
    my $kTargetValue = 'Target Value';
    my $kTargetValueDiff = 'Target Value Diff';
    my $kRebalance = 'Rebalance';
    my $kTargetBuy = 'Target Buy';
    my $kBuy = 'Buy';
    my $column_headers = [$kCategory, $kAllocTickers, $kOwnedTickers, $kValue,
			  $kAllocation, $kCurrentWeight, $kDifference,
			  $kDiffPercent, $kTargetValue, $kTargetValueDiff,
			  $kRebalance, $kTargetBuy, $kBuy];
    &Write_Csv_Line( $column_headers, $io, $csv );

    # $per_category_data->{$category}->{$header} = value
    my $per_category_data = {};

    # Two passes are needed because much depends on the total_portfolio_value
    my $total_portfolio_value = 0;
    my $total_alloc = 0;  # Just a sanity check
    foreach my $category (sort keys %{ $rhAssetAllocations->{$portfolio}->{'values'} }) {
	my $category_value = 0;
#	print "Category $category\n";
	my $raTickers = $rhAssetAllocations->{$portfolio}->{'tickers'}->{$category};
	my $alloc = $rhAssetAllocations->{$portfolio}->{'values'}->{$category} / 100.0;
	$total_alloc += $alloc;

	my @owned_tickers;
	my @alloc_tickers;
	foreach my $ticker (sort @{ $raTickers }) {
	    push @alloc_tickers, $ticker;
	    if ( defined $rhPrices->{$ticker} 
		 && defined $rhPerAcctShares->{$ticker} ) {
		my $price = $rhPrices->{$ticker};
		foreach my $acct ( sort @{ $rhPortfolioDefs->{$portfolio} } ) {
		    next unless defined $rhPerAcctShares->{$ticker}->{$acct};
		    my $shares = $rhPerAcctShares->{$ticker}->{$acct};
		    next if $shares < $gZero;
		    $category_value += $shares * $price;
		    push @owned_tickers, $ticker;
		}
	    }
	}
	$total_portfolio_value += $category_value;
	my $alloc_tickers = join(",", @alloc_tickers);
	my $owned_tickers = join(",", @owned_tickers);

	$per_category_data->{$category} = {};
	$per_category_data->{$category}->{$kCategory} = $category;
	$per_category_data->{$category}->{$kAllocTickers} = $alloc_tickers;
	$per_category_data->{$category}->{$kOwnedTickers} = $owned_tickers;
	$per_category_data->{$category}->{$kValue} = $category_value;
	$per_category_data->{$category}->{$kAllocation} = $alloc;
    }

    print "Total Asset Allocation isn't 1, it's \"$total_alloc\"\n";
    if ( $total_alloc != 1 ) {
	print "Warning: Total Asset Allocation isn't 1, it's \"$total_alloc\"\n";
    }

    # Set rebalance instructions
    my $excess_buy = 0;  # This is the sum of all the buys & sells proposed for rebalancing
    foreach my $category (sort keys %{ $rhAssetAllocations->{$portfolio}->{'values'} }) {
	my $value = $per_category_data->{$category}->{$kValue};
	my $current_weight = $value / $total_portfolio_value;
	$per_category_data->{$category}->{$kCurrentWeight} = $current_weight;
	
	my $difference = $per_category_data->{$category}->{$kAllocation} - $current_weight;
	$per_category_data->{$category}->{$kDifference} = $difference;

	my $diff_percent = 0;
	if ( $per_category_data->{$category}->{$kAllocation} != 0 ) {
	    $diff_percent = $difference / $per_category_data->{$category}->{$kAllocation};
	}
	$per_category_data->{$category}->{$kDiffPercent} = $diff_percent;

	my $target_value = $total_portfolio_value * $per_category_data->{$category}->{$kAllocation};
	$per_category_data->{$category}->{$kTargetValue} = $target_value;

	my $target_value_diff = $target_value - $value;
	$per_category_data->{$category}->{$kTargetValueDiff} = $target_value_diff;

	my $rebalance = 0;
	my $target_buy = 0;
	if ( abs($diff_percent) > 0.05 && abs($target_value_diff) > 5000 ) {
	    $rebalance = 1;
	    $target_buy = $target_value_diff;
	    $excess_buy += $target_buy;
	}	    
	$per_category_data->{$category}->{$kRebalance} = $rebalance;
	$per_category_data->{$category}->{$kTargetBuy} = $target_buy;
    }
    
    # Now write it out
    foreach my $category (sort
			  { $per_category_data->{$b}->{$kTargetValueDiff}
			    <=> $per_category_data->{$a}->{$kTargetValueDiff} }
			  keys %{ $per_category_data }) {
	&Write_Hash_To_Csv_Line($per_category_data->{$category}, $column_headers, $io, $csv);
    }
    my $totals = {};
    $totals->{$kValue} = $total_portfolio_value;
    $totals->{$kBuy} = $excess_buy;
    &Write_Hash_To_Csv_Line($totals, $column_headers, $io, $csv);
}

sub Write_Ticker_Lines {
    my $portfolio = shift;
    my $rhPortfolioDefs = shift;
    my $rhAssetAllocations = shift;
    my $rhPrices = shift;
    my $rhPerAcctShares = shift;
    my $raQPortfolioSecurityNames = shift;
    my $io = shift;
    my $csv = shift;

    my $ticker_headers = ["Name", "Ticker", "Account", "Price", "Shares"];
    &Write_Csv_Line( $ticker_headers, $io, $csv );
    
    foreach my $name (sort @{ $raQPortfolioSecurityNames }) {
	next if defined $Skip{$name};
	next if ( ! defined($Tickers{$name}) );
	my $ticker = $Tickers{$name};
	my $price = 'unknown';
	if ( defined($rhPrices->{$ticker}) ) {
	    $price = $rhPrices->{$ticker};
	}
	if ( defined $rhPerAcctShares->{$ticker} ) {
	    foreach my $acct ( sort @{ $rhPortfolioDefs->{$portfolio} } ) {
		next unless defined $rhPerAcctShares->{$ticker}->{$acct};
		my $shares = $rhPerAcctShares->{$ticker}->{$acct};
		next if $shares < $gZero;
		my $line = [$name, $ticker, $acct, $price, $shares];
		&Write_Csv_Line( $line, $io, $csv );
		if ( ! defined $rhAssetAllocations->{$portfolio}->{'categories'}->{$ticker} ) {
		    print "WARNING: No asset allocation class for ticker \"$ticker\"\n";
		    print "Add that ticker to asset-allocation-${portfolio}.csv\n";
		}
	    }
	}
    }
}

sub Write_Hash_To_Csv_Line {
    my $rhLine = shift;
    my $raFieldNames = shift;
    my $io = shift;
    my $csv = shift;

    my $line = [];
    foreach my $column ( @{ $raFieldNames }) {
	my $cell_value = '';
	if ( defined $rhLine->{$column} ) {
	    $cell_value = $rhLine->{$column};
	}
	push @{ $line }, $cell_value;
    }
    &Write_Csv_Line( $line, $io, $csv );
}

sub Write_Csv_Line {
    my $raFields = shift;
    my $io = shift;
    my $csv = shift;

    if ($csv->combine( @{ $raFields } )) {
	my $string = $csv->string;
	print $io $string, "\n";
    } else {
	my $err = $csv->error_input;
	print "combine () failed on argument: ", $err, "\n";
    }
}
