# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html

package xCAT::PPCboot;
use strict;
use Getopt::Long;
use xCAT::PPCcli qw(SUCCESS EXPECT_ERROR RC_ERROR NR_ERROR);


##########################################################################
# Parse the command line for options and operands 
##########################################################################
sub parse_args {

    my $request = shift;
    my %opt     = ();
    my $cmd     = $request->{command};
    my $args    = $request->{arg};
    my @VERSION = qw( 2.0 );

    #############################################
    # Responds with usage statement
    #############################################
    local *usage = sub {
        return( [ $_[0],
            "rnetboot -h|--help",
            "rnetboot -v|--version",
            "rnetboot [-V|--verbose] noderange",
            "    -h   writes usage information to standard output",
            "    -v   displays command version",
            "    -V   verbose output" ]);
    };
    #############################################
    # Process command-line arguments
    #############################################
    if ( !defined( $args )) {
        return( usage() );
    }
    #############################################
    # Checks case in GetOptions, allows opts
    # to be grouped (e.g. -vx), and terminates
    # at the first unrecognized option.
    #############################################
    @ARGV = @$args;
    $Getopt::Long::ignorecase = 0;
    Getopt::Long::Configure( "bundling" );

    if ( !GetOptions( \%opt, qw(h|help V|Verbose v|version) )) { 
        return( usage() );
    }
    ####################################
    # Option -h for Help
    ####################################
    if ( exists( $opt{h} )) {
        return( usage() );
    }
    ####################################
    # Option -v for version
    ####################################
    if ( exists( $opt{v} )) {
        return( \@VERSION );
    }
    ####################################
    # Check for "-" with no option
    ####################################
    if ( grep(/^-$/, @ARGV )) {
        return(usage( "Missing option: -" ));
    }
    ####################################
    # Check for an extra argument
    ####################################
    if ( defined( $ARGV[0] )) {
        return(usage( "Invalid Argument: $ARGV[0]" ));
    }
    $request->{method} = $cmd; 
    return( \%opt );
}


##########################################################################
# IVM rnetboot 
##########################################################################
sub ivm_rnetboot {

    my $request = shift;
    my $d       = shift;
    my $exp     = shift;
    my $name    = shift;
    my $opt     = shift;
    my $ssh     = @$exp[0];
    my $userid  = @$exp[4];
    my $pw      = @$exp[5];
    my $cmd;
    my $result;

    #######################################
    # Disconnect Expect session
    #######################################
    xCAT::PPCcli::disconnect( $exp );
    
    #######################################
    # Get node data 
    #######################################
    my $id       = @$d[0];
    my $pprofile = @$d[1];
    my $fsp      = @$d[2];
    my $hcp      = @$d[3];

    #######################################
    # Find Expect script 
    #######################################
    $cmd = ($::XCATROOT) ? "$::XCATROOT/sbin/" : "/opt/xcat/sbin/";
    $cmd .= "lpar_netboot.expect"; 

    #######################################
    # Check command installed
    #######################################
    if ( !-x $cmd ) {
        return( [RC_ERROR,"Command not installed: $cmd"] );
    }
    #######################################
    # Create random temporary userid/pw
    # file between 1000000 and 2000000
    #######################################
    my $random = int( rand(1000001)) + 1000000;
    my $fname = "/tmp/xCAT-$hcp-$random";

    unless ( open( CRED, ">$fname" )) {
        return( [RC_ERROR,"Error creating temporary password file '$fname'"]);
    }
    print CRED "$userid $pw\n";
    close( CRED );

    #######################################
    # Turn on verbose and debugging
    #######################################
    if ( exists($request->{verbose}) ) {
        $cmd.= " -v -x";
    }
    #######################################
    # Network specified
    #######################################
    $cmd.= " -s auto -d auto -m $opt->{m} -S $opt->{S} -G $opt->{G} -C $opt->{C}";
   
    #######################################
    # Add command options
    #######################################
    $cmd.= " -t ent -f \"$name\" \"$pprofile\" \"$fsp\" $id $hcp $fname";

    #######################################
    # Execute command
    #######################################
    if ( !open( OUTPUT, "$cmd 2>&1 |")) {
        return( [RC_ERROR,"$cmd fork error: $!"] );
    }
    #######################################
    # Get command output
    #######################################
    while ( <OUTPUT> ) {
        $result.=$_;
    }
    close OUTPUT;

    #######################################
    # If command did not, remove file
    #######################################
    if ( -r $fname ) {
        unlink( $fname );
    }
    #######################################
    # Get command exit code
    #######################################
    my $Rc = SUCCESS;

    foreach ( split /\n/, $result ) {
        if ( /^lpar_netboot: / ) {
            $Rc = RC_ERROR;
            last;
        }
    }
    return( [$Rc,$result] );
}


##########################################################################
# Get LPAR MAC addresses
##########################################################################
sub rnetboot {

    my $request = shift;
    my $d       = shift;
    my $exp     = shift; 
    my $hwtype  = @$exp[2];
    my $result;
    my $node;

    #####################################
    # Get node data 
    #####################################
    my $lparid = @$d[0];
    my $mtms   = @$d[2];
    my $type   = @$d[4];
    my $name   = @$d[6];
    my $o      = @$d[7]; 

    #####################################
    # Gateway (-G) 
    # Server  (-S) 
    # Client  (-C)
    # mac     (-m)
    #####################################
    my %opt = (
        G => $o->{gateway},
        S => $o->{server},
        C => $o->{client},
        m => $o->{mac}
    );
    #####################################
    # Invalid target hardware 
    #####################################
    if ( $type !~ /^lpar$/ ) {
        return( [[$name,"Not supported",RC_ERROR]] );
    }
    #########################################
    # Get name known by HCP
    #########################################
    my $filter = "name,lpar_id";
    my $values = xCAT::PPCcli::lssyscfg( $exp, $type, $mtms, $filter );
    my $Rc = shift(@$values);

    #########################################
    # Return error
    #########################################
    if ( $Rc != SUCCESS ) {
        return( [[$name,@$values[0],$Rc]] );
    }
    #########################################
    # Find LPARs by lpar_id
    #########################################
    foreach ( @$values ) {
        if ( /^(.*),$lparid$/ ) {
            $node = $1;
            last;
        }
    }
    #########################################
    # Node not found by lpar_id
    #########################################
    if ( !defined( $node )) {
        return( [[$name,"Node not found, lparid=$lparid",RC_ERROR]] );
    }
    #########################################
    # IVM does not have lpar_netboot command
    # so we have to manually perform boot. 
    #########################################
    if ( $hwtype eq "ivm" ) {
        $result = ivm_rnetboot( $request, $d, $exp, $node, \%opt );
    }
    else {
        $result = xCAT::PPCcli::lpar_netboot( 
                           $exp,
                           $request->{verbose}, 
                           $node,
                           $d,
                           \%opt );
    }
    my $Rc = shift(@$result);

    ##################################
    # Form string from array results
    ##################################
    if ( exists($request->{verbose}) ) {
        return( [[$name,join( '', @$result ),$Rc]] );
    }
    ##################################
    # Return error
    # lpar_netboot returns (for example):
    #  # Connecting to lpar1
    #  # Connected
    #  # Checking for power off.
    #  # Power off the node
    #  # Wait for power off.
    #  # Power off complete.
    #  # Power on lpar1 to Open Firmware.
    #  # Power on complete.
    #    lpar_netboot: can not find mac address 42DAB.
    #
    ##################################
    if ( $Rc != SUCCESS ) {
        if ( @$result[0] =~ /lpar_netboot: (.*)/ ) {
            return( [[$name,$1,$Rc]] );
        }
        return( [[$name,join( '', @$result ),$Rc]] );
    }
    ##################################
    # Split array into string
    ##################################
    my $data = @$result[0];
    if ( $hwtype eq "hmc" ) {
        $data = join( '', @$result );
    }
    ##################################
    # lpar_netboot returns:
    #
    #  # Connecting to lpar1
    #  # Connected
    #    ...
    #  lpar_netboot Status: network boot initiated
    #  # bootp sent over network.
    #  lpar_netboot Status: waiting for the boot image to boot up.
    #  # Network boot proceeding, lpar_netboot is exiting.
    #  # Finished.
    #
    #####################################
    if ( $data =~ /Finished/) {
        return( [[$name,"Success",$Rc]] );
    }
    #####################################
    # Can still be error w/ Rc=0:
    #
    #  # Connecting to lpar1
    #  # Connected
    #    ...
    #  lpar_netboot Status: network boot initiated
    #  # bootp sent over network.
    #  lpar_netboot Status: waiting for the boot image to boot up.
    #  lpar_netboot: bootp operation failed.
    #
    #####################################
    if ( $data =~ /lpar_netboot: (.*)/ ) {
        return( [[$name,$1,RC_ERROR]] );
    }
    return( [[$name,$data,RC_ERROR]] );
}
 

1;





