
package Util;
require Exporter;
@ISA = qw(Exporter);
@EXPORT_OK = qw(writeHashToCsvLine writeCsvLine);

sub writeHashToCsvLine {
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

sub writeCsvLine {
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


