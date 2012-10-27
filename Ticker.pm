#!/bin/perl

# A ticker represents an asset that can be held in a portfolio.  It
# has a symbol, like GOOG and a name like Google.  This class holds
# information about the ticker itself, rather than any shares of that
# ticker.
#
# One way to get ticker information is to create a Google Docs
# spreadsheet and use the =GoogleFinance() function in it to grab the
# needed info directly from google finance.  Then download this as a
# CSV file.
# See http://blog.growth5.com/2009/10/scraping-web-with-google-docs.html
# https://support.google.com/docs/bin/answer.py?hl=en&answer=155178
#
# An alternative I haven't yet tried is to scrape it directly and/or
# into an excel spreadsheet.  Scraping directly will be tricky because
# the sites I want to scrape use AJAX, so it will require a Javascript
# interpreter to render the page before it can be scraped.
# Some links:
# http://stackoverflow.com/questions/6704209/downloading-morningstar-webpages-for-screenscraping
# http://finance.groups.yahoo.com/group/smf_addin/files/

package Ticker;
require Exporter;
@ISA = qw(Exporter);
@EXPORT_OK = qw($kCash);

use Text::CSV_XS;
use strict;
use warnings;
use AssetClass qw($US_STOCK $INTL_STOCK $BOND $REAL_ASSET $CASH);

#-----------------------------------------------------------------
# Initialization
#-----------------------------------------------------------------

my $gDebug = 1;

# Decided to treat cash as its own ticker type.
# So, from a ticker perspective it will be consistent.
our $kCash = '-Cash-';

our $gUnknown = 'Unknown';

# #
# # Every ticker ever purchased should be either in Skip or in Tickers
# #
my %Skip = (
    '2004-07 DP407070 Bin' => '1',
    '2007-07 FS783025 Bin' => '1',
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
    'CALL XILINX INC$22.50 EXP 11/18/06' => 'XLQKX',
    'CALL XILINX INC$22.50 EXP 04/18/09' => 'XLQDX',
    'CALL XILINX INC$25 EXP 03/22/08' => 'XLQCE',
    'CALL XILINX INC$25 EXP 04/19/08' => 'XLQDE',
    'CALL XILINX INC$25 EXP 06/21/08' => 'XLQFE',
    'CALL XILINX INC$25 EXP 07/19/08' => 'XLQGE',
    'CALL XILINX INC$25 EXP 10/21/06' => 'XLQJE',
    'CALL XILINX INC$25 EXP 11/18/06' => 'XLQKE',
    'CALL XILINX INC$25 EXP 12/16/06' => 'XLQLE',
    'CALL XILINX INC$27.50 EXP 03/17/07' => 'XLQCY.x',
    'CALL XILINX INC$27.50 EXP 05/19/07' => 'XLQEY',
    'CALL XILINX INC$27.50 EXP 06/16/07' => 'XLQFY',
    'CALL XILINX INC$27.50 EXP 09/20/08' => 'XLQIY',
    'CALL XILINX INC$27.50 EXP 11/17/07' => 'XLQKY',
    'CALL XILINX INC$30 EXP 09/22/07' => 'XLQIF',
    'CALL XILINX INC$21 EXP 08/22/09' => '',
    'CALL XILINX INC$25 ADJ EXP 01/20/07' => '',
    'CALL XILINX INC$25 EXP 10/18/08' => '',
    'CALL XILINX INC$30 EXP 09/16/06' => '',
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
    'VANGUARD EXTENDED MKT FDSTK MKT VIPERS' => 'VXF',
    'Vanguard FTSE All-World ex-US Index Fund Investor Shares' => '',
    'Vanguard High-Yield Corporate Fund Investor Shares' => 'VWEHX',
    'Vanguard Intermediate-Term BOND Index Fund Admiral Shares' => 'VBILX',
    'Vanguard Long-Term Treasury Fund Investor Shares' => 'VUSUX', # all became VUSUX
    'VANGUARD MATERIALS' => 'VAW',
    'Vanguard Mid-Cap Index Fund Investor Shares' => 'VIMAX', # converted to adm
    'Vanguard SP 500 index' => 'VFINX',  # This was transfered to VFIAX
    'VANGUARD LONG-TERM CORPORATE BOND' => 'VWESX',
    # 'Vanguard Inflation-Protected Securities Fund Investor Shares' => 'VIPSX',
    'VANGUARD INTERNATIONAL VALUE' => 'VTRIX',
    'Vanguard Pacific Stock Index Fund Investor Shares' => 'VPACX',
    'VANGUARD SHORT-TERM FEDERAL' => 'VSGBX',
    'Vanguard Small-Cap Growth Index Fund' => 'VISGX',
    'Vanguard Small-Cap Value Index Fund' => 'VISVX',
#    'Vanguard Tax-Exempt Money Market Fund' => '',
    'VIRTUS INSIGHT SMALL CAP VALUE A' => 'HSVZX',
    'VODAFONE AIRTOUCH PLC SP ADR' => '1',
    'Wal-Mart Stores Inc' => '1',
    'XILINX INC' => '1',
    'Xilinx' => '1',
    'XILINX INC ESPP' => 'XLNX',
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

# my %Tickers = (
#     $kCash => $kCash,
#     $gUnknown => 0,
#     'American Funds Growth Fund of Amer R4' => 'RGAEX',
#     'Columbia Mid Cap Value Z' => 'NAMAX',
#     'Eaton Vance Large-Cap Value I' => 'EILVX',
#     'EXCELSIOR VALUE AND RESTRUCTURING FUND' => 'UMBIX',
#     'FAIRHOLME FUND' => 'FAIRX',
#     'Harbor International Instl' => 'HAINX',
#     'IPATH DOW JONES-UBS COMMODITY INDEX TOTAL RETURN ETN' => 'DJP',
#     'LOOMIS SAYLES GLOBAL BOND/RETAIL' => 'LSGLX',
#     'Nuveen Winslow Large-Cap Growth I' => 'NVLIX',
#     'PIMCO Total Return Instl' => 'PTTRX',
#     'RIDGEWORTH US GOV SEC ULTRA SHORT BD I' => 'SIGVX',
#     'Royce Low Priced Stock Svc' => 'RYVPX',
#     'SCHWAB S&P 500 INDEX SEL' => 'SWPPX',
#     'SPDR GOLD TRUST GOLD SHARES' => 'GLD',
#     'THIRD AVENUE VALUE FUND' => 'TAVFX',
#     'T. Rowe Price Instl Large Cap Value' => 'TILCX',
#     'UMB SCOUT WORLDWIDE FUND' => 'UMBWX',
#     'Vanguard 500 Index Fund Signal Shares' => 'VIFSX',
#     'Vanguard Wellington Adm' => 'VWENX',
#     'Vanguard California Intermediate-Term Tax-Exempt Fund Investor Shares' => 'VCAIX',
#     'Vanguard Convertible Securities Fund' => 'VCVSX',
#     'VANGUARD DIVIDEND APPRECIATION ETF' => 'VIG',
#     'VANGUARD EMERGING MARKET' => 'VWO',
#     'Vanguard Emerging Markets Stock Index Fund Admiral Shares' => 'VEMAX',
#     'VANGUARD ENERGY ETF' => 'VDE',
#     'Vanguard Energy Fund Investor Shares' => 'VGENX',
#     'Vanguard Extended Market Index Fund Investor Shares' => 'VEXMX',
#     'VANGUARD FTSE ETF **PENDING ENLISTMENT* --BEST EFFOR' => 'VSS',
#     'Vanguard FTSE All-World ex-US Index Fund Admiral' => 'VFWAX',
#     'Vanguard FTSE All-World ex-US Small-Cap Index Fund Investor Shares' => 'VFSVX',
#     'VANGUARD GLOBAL EQUITY FUND INVESTOR SHARE' => 'VHGEX',
#     'Vanguard GNMA Fund Admiral Shares' => 'VFIJX',
#     'Vanguard High-Yield Corporate Fund Admiral Shares' => 'VWEAX',
#     'Vanguard Inflation-Protected Securities Fund Admiral Shares' => 'VAIPX',
#     'Vanguard Intermediate-Term Investment-Grade Fund Admiral Shares' => 'VFIDX',
#     'Vanguard Intermediate-Term Bond Index Fund Admiral Shares' => 'VBILX',
#     'Vanguard International Equity Index Funds' => 'VNQI',
#     'VANGUARD INTL EQTY INDEXFTSE ALL WORLD EX US ETF' => 'VEU',
#     'Vanguard Long-Term Treasury Fund Admiral Shares' => 'VUSUX',
#     'VANGUARD MEGA CAP 300 INDEX ETF' => 'MGC',
#     'VANGUARD MID CAP ETF' => 'VO',
#     'Vanguard Mid-Cap Growth Fund' => 'VMGRX',
#     'Vanguard Mid-Cap Index Fund Admiral Shares' => 'VIMAX',
#     'Vanguard Prime Money Market Fund' => 'VMMXX',
#     'VANGUARD REIT' => 'VNQ',
#     'Target Retirement 2030 Trust I' => 'VTHRX',
#     'VANGUARD SHORT TERM BOND ETF' => 'BSV',
#     'VANGUARD SMALL-CAP VIPERS' => 'VB',
#     'VANGUARD TOTAL INTL STOCK INDEX' => 'VGTSX',
#     'Vanguard Wellesley Income Adm' => 'VWIAX',
#     'Victory Inst Diversified Stock' => 'VIDSX',
#     'William Blair International Growth N' => 'WBIGX',
#     );

# my %AssetClass = (
#     $kCash => $AssetClass::CASH,
#     'ARTKX' => $AssetClass::INTL_STOCK,
#     'ARTQX' => $AssetClass::US_STOCK,
#     'AVPAX' => $AssetClass::US_STOCK,
#     'BEGBX' => $AssetClass::BOND,
#     'BIOPX' => $AssetClass::US_STOCK,
#     'BRK.B' => $AssetClass::US_STOCK,
#     'BSV' =>   $AssetClass::BOND,
#     'BTTRX' => $AssetClass::BOND,
#     'CFICX' => $AssetClass::BOND,
#     'DJP' => $AssetClass::REAL_ASSET,
#     'DODFX' => $AssetClass::INTL_STOCK,
#     'DODGX' => $AssetClass::US_STOCK,
#     'EILVX' => $AssetClass::US_STOCK,
#     'ETRUX' => $AssetClass::US_STOCK,
#     'FAIRX' => $AssetClass::INTL_STOCK | $AssetClass::US_STOCK,
#     'FBRSX' => $AssetClass::US_STOCK,
#     'FFSCX' => $AssetClass::US_STOCK,
#     'FXI'   => $AssetClass::INTL_STOCK,
#     'GLD' => $AssetClass::REAL_ASSET,
#     'GMF'   => $AssetClass::INTL_STOCK,
#     'HAINX' => $AssetClass::INTL_STOCK,
#     'HSVZX' => $AssetClass::US_STOCK,
#     'ISLCX' => $AssetClass::US_STOCK,
#     'JASCX' => $AssetClass::US_STOCK,
#     'JMCVX' => $AssetClass::US_STOCK,
#     'LSGLX' => $AssetClass::BOND,
#     'MGC' => $AssetClass::US_STOCK,
#     'MSSFX' => $AssetClass::US_STOCK,
#     'NAMAX' => $AssetClass::US_STOCK,
#     'NVLIX' => $AssetClass::US_STOCK,
#     'PTTRX' => $AssetClass::BOND,
#     'RGAEX' => $AssetClass::US_STOCK | $AssetClass::INTL_STOCK,
#     'RISIX' => $AssetClass::INTL_STOCK,
#     'RSVAX' => $AssetClass::US_STOCK,
#     'RYVPX' => $AssetClass::US_STOCK | $AssetClass::INTL_STOCK,
#     'SASPX' => $AssetClass::INTL_STOCK,
#     'SCUIX' => $AssetClass::US_STOCK,
#     'SEQUX' => $AssetClass::US_STOCK,
#     'SIGVX' => $AssetClass::CASH,
#     'SPY'   => $AssetClass::US_STOCK,
#     'SSREX' => $AssetClass::US_STOCK,
#     'SWHFX' => $AssetClass::US_STOCK,
#     'SWPPX' => $AssetClass::US_STOCK,
#     'TAREX' => $AssetClass::US_STOCK | $AssetClass::INTL_STOCK,
#     'TAVFX' => $AssetClass::US_STOCK | $AssetClass::INTL_STOCK,
#     'TILCX' => $AssetClass::US_STOCK,
#     'TRMCX' => $AssetClass::US_STOCK,
#     'TRP' => $AssetClass::INTL_STOCK,
#     'TWCVX' => $AssetClass::US_STOCK,
#     'UMBIX' => $AssetClass::US_STOCK | $AssetClass::INTL_STOCK,
#     'UMBWX' => $AssetClass::INTL_STOCK,
#     'VAIPX' => $AssetClass::BOND,
#     'VAW'   => $AssetClass::US_STOCK,
#     'VB' => $AssetClass::US_STOCK,
#     'VBILX' => $AssetClass::BOND,
#     'VCAIX' => $AssetClass::BOND,
#     'VCVSX' => $AssetClass::BOND,
#     'VDE' =>   $AssetClass::US_STOCK,
#     'VEIEX' => $AssetClass::INTL_STOCK,
#     'VEU' => $AssetClass::INTL_STOCK,
#     'VEMAX' => $AssetClass::INTL_STOCK,
#     'VEXMX' => $AssetClass::US_STOCK,
#     'VFIDX' => $AssetClass::BOND,
#     'VFIAX' => $AssetClass::US_STOCK,
#     'VFIJX' => $AssetClass::BOND,
#     'VFSVX' => $AssetClass::INTL_STOCK,
#     'VFWAX' => $AssetClass::INTL_STOCK,
#     'VFWIX' => $AssetClass::INTL_STOCK,
#     'VGENX' => $AssetClass::US_STOCK | $AssetClass::INTL_STOCK,
#     'VGTSX' => $AssetClass::INTL_STOCK,
#     'VHGEX' => $AssetClass::US_STOCK | $AssetClass::INTL_STOCK,
#     'VIDSX' => $AssetClass::US_STOCK,
#     'VIFSX' => $AssetClass::US_STOCK,
#     'VIG' =>   $AssetClass::US_STOCK,
#     'VIMAX' => $AssetClass::US_STOCK,
#     'VIMSX' => $AssetClass::US_STOCK,
#     'VIPSX' => $AssetClass::BOND,
#     'VISGX' => $AssetClass::US_STOCK,
#     'VISVX' => $AssetClass::US_STOCK,
#     'VMGRX' => $AssetClass::US_STOCK,
#     'VMMXX' => $AssetClass::CASH,
#     'VNQ'   => $AssetClass::US_STOCK,
#     'VO' => $AssetClass::US_STOCK,
#     'VPACX' => $AssetClass::INTL_STOCK,
#     'VSS'   => $AssetClass::INTL_STOCK,
#     'VTHRX' => $AssetClass::INTL_STOCK | $AssetClass::US_STOCK | $AssetClass::BOND,
#     'VUSTX' => $AssetClass::BOND,
#     'VUSUX' => $AssetClass::BOND,
#     'VWEAX' => $AssetClass::BOND,
#     'VWEHX' => $AssetClass::BOND,
#     'VWO'   => $AssetClass::INTL_STOCK,
#     'VXF'   => $AssetClass::US_STOCK,
#     'WBIGX' => $AssetClass::INTL_STOCK,
#     'WWNPX' => $AssetClass::US_STOCK | $AssetClass::INTL_STOCK,
#     );

my %Tickers;

my $TickersBySymbol = {};
my $TickersByName = {};

&InitializeFromCsv('quicken/ticker-info.csv');

#-----------------------------------------------------------------
# Methods
#-----------------------------------------------------------------

sub InitializeFromCsv {
    my ($fname) = @_;

    $gDebug && print "Try to read $fname\n";
    my $csv = Text::CSV_XS->new ({ binary => 1, eol => $/ });
    if ( open my $io, "<", $fname ) {

	# The rest of the header names act as hash indices
	my $header = $csv->getline ($io);
	if ($header->[0] ne "_ticker"
	    || $header->[1] ne "_name"  
	    || $header->[2] ne "_skip" ) {
	    print "Header incorrect in $fname\n";
	    return;
	}
    
	while (my $row = $csv->getline($io)) {
	    # print "\"", join(", ", @{ $row }), "\"\n";
	    my $symbol = $row->[0];
	    my $name = $row->[1];

	    # Local skip overrides the spreadsheet value.
	    my $skip = (defined($Skip{$name}));
	    $skip = $row->[2] unless ($skip);
	
	    my $ticker = Ticker->new($name, $symbol, $skip);
	    my $last_row_index = scalar(@{ $row })-1;
	    foreach my $i (3 .. $last_row_index) {
		$ticker->{$header->[$i]} = $row->[$i];
	    }
	}
    } else {
	die "Can't open $fname";
    }
}

sub new
{
    my $class = shift;
    my $self = {
	_name => shift,   # Must be defined
        _symbol => shift, # Must be defined
        _skip  => shift,  # Must be defined
	# Other attributes are accessed by name
    };

    # Must provide name and symbol
    if ( !defined( $self->{_symbol} ) || !defined( $self->{_name} ) ) {
	print "** Ticker object must provide symbol and name.\n";
	die "";
    }

    bless $self, $class;
    $TickersBySymbol->{ $self->{_symbol} } = $self;
    $TickersByName->{ $self->{_name} } = $self;
    return $self;
}

sub name { $_[0]->{_name}; }
sub symbol { $_[0]->{_symbol}; }
sub skip { $_[0]->{_skip}; }
sub attribute { $_[0]->{$_[1]}; }

sub getByName
{
    my $name = shift;

    # Share the objects instead of allocating new ones.
    if ( defined($name) && defined($TickersByName->{$name})) {
	return $TickersByName->{ $name };
    }

    # Get the skip value.  Skip most stuff for this ticker.
    my $skip = (defined($Skip{$name}));
    
    # Get the symbol from the name
    my $symbol;
    if (defined($Tickers{ $name })) {
	$symbol = $Tickers{ $name };
    } elsif ($skip) {
	# Will skip most stuff for this ticker
	$symbol = $gUnknown;
    } else {
	if (ref($name) ne '') {
	    die "$name shouldn't be a ref";
	}
	my $msg = "** Add the following to \%Tickers or "
	    . "\%Skip in Ticker.pm\n"
	    . "    '" . $name . "' => '',\n";
	die $msg;
    }

    return Ticker->new($name, $symbol, $skip);
}

sub getBySymbol
{
    my $symbol = shift;

    # Get the Name for this symbol
    if ( !defined($TickersBySymbol->{$symbol})) {
	die "Add Symbol \"$symbol\" to Ticker.pm";
    }
    return $TickersBySymbol->{$symbol};
}

sub printToStringArray
{
    my($self, $raS, $prefix) = @_;
    
    foreach my $k ( sort keys %{ $self } ) {
	push @{$raS}, sprintf("%s  \"%s\": \"%s\"", $prefix, $k,
			      $self->{$k});
    }
}

sub Print
{
    my ($self) = @_;
    print 'Ticker: Symbol = ', $self->{_symbol};
}

1;
