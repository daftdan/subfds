#!/usr/bin/perl
# subfds - generate a PBS submission file for FDS v4 or 5 based on inferred
# information and user-provided input
use warnings;
use strict;
use Data::Dumper;
use Cwd;

## Defaults
my $fds_version		= "6.7.0";
my $fds_major_version	= 6;
my $cpus_to_use		= 2;
my $cpn			= 20; # number of CPUs in each node
my $edit_command_line	= "";
my $ready_to_run	= 0;
my $queue		= "fds";
my $mpi_cpu_arg		= "";
my $mesh_keyword	= "&MESH";
my $job_name;
my $input_file;
my $cwd			= cwd() ;

#my %available_fds_versions;
my %available_fds_versions = (
	"6.6.0" => "/prg/fds/6.6.0",
	"6.7.0" => "/prg/fds/6.7.0",
	"6.7.3" => "/prg/fds/6.7.3",
	"6.7.9" => "/prg/fds/6.7.9"
	);

#foreach my $directory_name (</prg/fds/x86_64/fds-mpi-6*>) {
#	my $fire_version;
#	if($directory_name =~ m!/prg/fds/x86_64/fds-mpi-([.\d]+)!) {
#		$fire_version = $1;
#		chomp $fire_version;
#		$available_fds_versions{$fire_version} = $directory_name;
#	}
#}

my $max_cpus = 40;

$input_file = select_input_file("fds");
($job_name = $input_file) =~ s/\.fds$//i;

# enumerate "MESH"es, different spatial domains defined in the 
# input data and set the same number of CPUs
open (my $input_file_handle, '<', $input_file)
	or die "Unable to read input file: $!\n";
my $spatial_domains = grep(/^$mesh_keyword/, <$input_file_handle>);
$cpus_to_use = $spatial_domains;

while(!$ready_to_run) {
	display_status();
	my $input = <STDIN>;
	chomp $input;
	$input = lc $input;
	if($input =~ /^i/i) {
		$input_file = select_input_file("fds");
		($job_name = $input_file) =~ s/\.fds$//i;
		# enumerate "MESH"s, different spatial domains defined in the input data
		# and set the same number of CPUs
		open (my $input_file_handle, '<', $input_file)
			or die "Unable to read input file: $!\n";
		my $spatial_domains = grep(/^$mesh_keyword/, <$input_file_handle>);
		$cpus_to_use = $spatial_domains;
	}
	elsif($input =~ /^g/i) {
		if($input_file and $cpus_to_use and $fds_version) {
			launch_job();
		}
		else {
			print "You need to specify at least an input file, the number of CPUs, and the FDS version.\n";
			print "Press [ENTER] to continue.\n";
			my $discard = <STDIN>;
		}
	}
    elsif($input =~ /^v/i) {
        $fds_version = select_version();
    }
	elsif($input =~ /^cp/i) {
		$cpus_to_use = select_cpu_count();
		#~ print "$cpus_to_use\n$spatial_domains\n";
		if ($cpus_to_use < $spatial_domains) {
			#~ print "$cpus_to_use < $spatial_domains\n";
			mesh_distribution();
		}
		#~ my $junk = <STDIN>;
	}
    elsif($input =~ /^cm/i) {
        $edit_command_line = "true";
    }
    elsif($input =~ /^(exit|quit)/i) {
        exit(0);
    }
}

sub launch_job {
	# Create the script to submit to PBS.
	my $launch_filename = $job_name . ".qsub.sh";
	open(my $fh, ">", $launch_filename)
		or die "Unable to open $launch_filename: $!\n";

	my $node_resource;
	if($cpus_to_use < $cpn) {
		$node_resource = "1:ppn=$cpus_to_use";
	} else {
		$node_resource = int($cpus_to_use/$cpn) . ":ppn=$cpn" . ($cpus_to_use % $cpn ? "+1:ppn=" . $cpus_to_use % $cpn : "" );
	}

	my $cwd  = getcwd();

	my $prog_to_run = $available_fds_versions{$fds_version};

	print $fh <<"EOSCRIPT";
#!/bin/sh
#
#PBS -N $job_name
#PBS -q $queue
#PBS -l nodes=$node_resource
#PBS -W umask=0007
##PBS -d $cwd
##PBS -o \$PBS_JOBNAME.o\$PBS_JOBID.txt
##PBS -e \$PBS_JOBNAME.e\$PBS_JOBID.txt
cd \$PBS_O_WORKDIR
ulimit -s unlimited
module load $available_fds_versions{$fds_version}/modules/fds6
mpiexec -rmk pbs fds \$PBS_O_WORKDIR/$input_file 2>&1 | tee \$PBS_O_WORKDIR/\$PBS_JOBNAME.mon
EOSCRIPT
	close($fh);

	#Edit the script if requested, use $EDITOR if possible, vim otherwise.
	if($edit_command_line) {
		$ENV{EDITOR} ||= "vim";
		system($ENV{EDITOR}, $launch_filename);
	}

	#Submit the job to PBS
	system("qsub", $launch_filename);
	exit();
}

sub display_status {
	system('clear');
	no warnings "uninitialized";
	print <<EOMESSAGE;

FDS 6.6.0+ Job Submission: 2018-07-01

Submission Status:

Job Name                   : $job_name
Input file            (inp): $input_file
FDS Version           (ver): $fds_version
Number of CPUs        (cpu): $cpus_to_use
Edit FDS Command Line (cmd): $edit_command_line

To edit the job options, enter one of the following:
"inp", "ver", "cpu", "cmd", or "go" to submit the 
job. "exit" will exit.
EOMESSAGE
}

sub select_input_file {
    my $extension = shift;
    system('clear');
    print "\n\n\n\nPlease select the appropriate file from the list below\n";
    my @input_files = (<*.$extension>);

    if(scalar (@input_files) == 0) {
        print "\nNo files with an extension of $extension found. Press [ENTER] to continue.\n";
        my $foo = <STDIN>;
        return undef;
    } elsif(scalar (@input_files) == 1) {
        print "\nAutomatically selecting " . $input_files[0] . ". Press [ENTER] to continue.\n";
        my $foo = <STDIN>;
        return($input_files[0]);
    }
    #Show a list of available files
    for(my $i=0 ; $i <= $#input_files ; $i++) {
        my $t = $i+1;
        print "$t) " . $input_files[$i] . "\n";
    }

    print "\n";
    my $selected_input_file;
    until ($selected_input_file) {
        my $user_input = <STDIN>;
        chomp $user_input;
        $user_input =~ s/\D*//g; # Numbers only, pleases
        if(length($user_input) and $user_input >= 1 and $user_input <= $#input_files+1) {
            my $index = $user_input - 1;
            $selected_input_file = $input_files[$index];
        }
        else {
            warn "Please select a number between 1 and $#input_files\n";
        }
    }
    return $selected_input_file;
}

sub select_version {
    system('clear');
    print "\n\n\n\nPlease select the required FDS version\n";
    print "Available versions: ", join("\n  ", "", sort keys %available_fds_versions), "\n";
    my $selected_version;
    until ($selected_version) {
        my $user_input = <STDIN>;
        chomp $user_input;
        $user_input =~ s/[^.0-9]*//g; # Numbers and dots

        if(exists($available_fds_versions{$user_input})) {
            $selected_version = $user_input
        }
        else {
            warn "Please select a version from the list\n";
        }
    }
    return $selected_version;
}

sub mesh_distribution {
	print "You have chosen fewer CPUs than there are spatial domains, therefore you will 
need to specify the distribution of spatial domains across CPUs.\n";
	my @distribution;

	for (my $i=1;$i<=$spatial_domains;$i++) {
		LABEL: print "Enter CPU for mesh $i (1 - $cpus_to_use): ";
		my $ans=<STDIN>;
		chop $ans;
		if ( $ans > $cpus_to_use ) {
			print "You have entered a number higher than the number of CPUs requested \($cpus_to_use)\n
Please re-enter CPU number \n";
			goto LABEL;
		}
		push(@distribution,$ans -1);
	} 
	$mpi_cpu_arg = "c".join(",", @distribution);
}
	
sub select_cpu_count {
    system('clear');
    print "\n\n\n\nPlease select the required number of CPUs (1-$max_cpus)\n";
    my $selected_count;
    until ($selected_count) {
        my $user_input = <STDIN>;
        chomp $user_input;
        $user_input =~ s/\D*//g; # Numbers only, pleases

        if($user_input and 1 <= $user_input and $user_input <= $max_cpus) {
            $selected_count = $user_input
        }
        else {
            warn "Please select a valid number between 1 and $max_cpus \n";
        }
    }
    return $selected_count;
}
