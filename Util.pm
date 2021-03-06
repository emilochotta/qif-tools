
package Util;
require Exporter;
@ISA = qw(Exporter);
@EXPORT = qw(writeHashToCsvLine writeCsvLine);

use Text::CSV_XS;

sub minimum {
    my ($a, $b) = @_;
    return ($a < $b) ? $a : $b;
}

sub maximum {
    my ($a, $b) = @_;
    return ($a > $b) ? $a : $b;
}

sub printHashToCsv {
    my $rhLine = shift;        # in: Hash of data
    my $raFieldNames = shift;  # in: Field names to pull out of the hash
    my $rhNameMap = shift;     # in: If defined, FieldNames contains keys into
                               #     rhNameMap, and the values are the keys into
                               #     rhLine.
    my $csv = shift;           # in: CSV object to do the work
    my $raS = shift;           # out: add output to this array of strings 

    my $line = [];
    foreach my $key ( @{ $raFieldNames }) {
	my $cell_value = '';
	my $column = $key;
	if ( defined($rhNameMap) && defined($rhNameMap->{$key}) ) {
	    $column = $rhNameMap->{$key};
	}
	if ( defined $rhLine->{$column} 
	     && ref($rhLine->{$column}) eq '') {
	    $cell_value = $rhLine->{$column};
	}
	push @{ $line }, $cell_value;
    }
    &printCsv( $line, $csv, $raS );
}

sub printCsv {
    my $raFields = shift;  # in: Array of data to put into cells
    my $csv = shift;       # in: CSV formating object
    my $raS = shift;       # out: Append resulting CSV string to this

    if ($csv->combine( @{ $raFields } )) {
	my $string = $csv->string();
	# strip $string;
	push @{$raS}, $string;
    } else {
	my $err = $csv->error_input;
	my $msg = "combine () with error: \"$err\"\n on input \"".
	    join("\", \"",@{$raFields}). "\"";
	print STDERR $msg, "\n";
	push @{$raS}, $string;
    }
}

sub intersect {
    my ($a, $b) = @_;
    @union = @intersection = @difference = ();
    %count = ();
    foreach $element (@$a, @$b) { $count{$element}++ }
    foreach $element (keys %count) {
            push @union, $element;
            push @{ $count{$element} > 1 ? \@intersection : \@difference }, $element;
    }
    return \@intersection;
}
	
