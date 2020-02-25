#!/usr/local/bin/perl
# Auther  : BlackMickey
# Version : 20200225

# You can run it like this:
# 1. Create a screen (ex: screen -dmS cleaner)
# 2. Go to that screen (ex: screen -r cleaner)
# 3. perl cleaner.pl
# You'll know it's working when you see torrents being deleted, 
# and it also outputs the ID of the torrent that is being deleted.

############### Parameters ###############

# Maximum storage capacity.(GB)
$disk_space_MAX = 1000;

# The script starts when the disk remaining capacity is less than this percentage.(%)
$disk_threshold_per = 15;

# The script starts when the disk remaining capacity is less than this value.(GB)
$disk_threshold = 150;

# Save path
$data_path = "/home/Downloads";

# Period. (Minutes)
$Period_min = 10;

# Save log
$save_log = 0;

##########################################

$datestring = localtime();
$port_info = `grep '"daemon_port": [0-9]*' ~/.config/deluge/core.conf`;
$port_info =~ /(\d+)/;
$port = $1;

print "Local date and time $datestring\n";
print "Loading...\n";
print "Period       : $Period_min minutes\n"; 
print "data_path    : $data_path\n";
print "deluge_port  : $port\n";
if( $save_log == 1 ){
    print "Save log     : True\n";
}else{
    print "Save log     : False\n";
}
print "disk_space_MAX (GB)    : $disk_space_MAX\n";
print "disk_threshold_per (%) : $disk_threshold_per\n";
print "disk_threshold (GB)    : $disk_threshold\n";
sleep 5;

my %local_collection;

local *get_deluge_info = sub {
    my $info = `deluge-console "connect 127.0.0.1:$port; info"`;
    my @collection;
    while ($info =~ /(?:Name:\s)(.+)\n(?:ID:\s)([a-z0-9]+)\n(?:State:\s)(.+)\n(?:Seeds:\s)(.+)\n(?:Size:\s)(.+)\n(?:Seed time:\s)(.+)\n(?:Tracker status:\s)(.+)(?:\n(?:Progress:\s)(\d+))?/ig) {
        # this could be auto-gen by removing the non capture
        my %deluge_obj = (
            'name' => $1,
            'id' => $2,
            'state' => $3,
            'seeds' => $4,
            'size' => $5,
            'seed_time' => $6,
            'tracker_status' => $7,
        );
        my $c = $8 || '';
        
        
        # ignore incomplete
        next if($deluge_obj{'state'} !~ /seeding/i && $c !~ /100/i);
        
        
        # set seed_time
        $deluge_obj{'seed_time'} =~ /^(\d+)\s([a-z]+)\s(?:([\d]+):(\d+):(\d+))/i;
        $deluge_obj{'seed_time'} = $1 * 24 + $3;

        # set Speed
        $deluge_obj{'state'} =~ /(?:Up Speed:\s)([\d\.]+)\s([a-z]+)/i;
        my %speed = (
            'speed' => 0,
            'unit' => '',
        );
        $speed{'speed'} = $1;
        $speed{'unit'} = $2;
        $deluge_obj{'speed'} = \%speed;

        # set Ratio
        $deluge_obj{'size'} =~ /^([\d\.]+)\s([a-z]+).([\d\.]+)\s([a-z]+)\s([a-z]+):\s([\d\.]+)/i;
        $deluge_obj{'ratio'} = $6;

        # set Size
        next if ($3 <= /0/i); # 防止太快抓到種子時誤刪，但未產生流量的未註冊種子無法自動刪除，待修改
        my %file_size = (
            'size' => 0,
            'unit' => '',
        );
        $file_size{'size'} = $3;
        $file_size{'unit'} = $4;
        $deluge_obj{'file_size'} = \%file_size;

        # set Downloaded
        my %downloaded = (
            'size' => 0,
            'unit' => '',
        );
        $downloaded{'size'} = $1;
        $downloaded{'unit'} = $2;
        $deluge_obj{'downloaded'} = \%downloaded;
        
        push @collection, \%deluge_obj;
    }
    return \@collection;
};

# normalize speed to a base unit of MiB/s
local *normalize = sub {
    my $obj = shift;
    if ($obj->{'unit'} =~ /KiB/i) {
        return $obj->{'speed'} /= 1024;
    }
    if ($obj->{'unit'} =~ /GiB/i) {
        return $obj->{'speed'} *= 1024;
    }
    return $obj->{'speed'};
};

# normalize size to a base unit of GiB
local *normalize_size = sub {
    my $obj = shift;
    if ($obj->{'unit'} =~ /KiB/i) {
        return $obj->{'size'} /= 1048576;
    }
    if ($obj->{'unit'} =~ /MiB/i) {
        return $obj->{'size'} /= 1024;
    }
    if ($obj->{'unit'} =~ /TiB/i) {
        return $obj->{'size'} *= 1024;
    }
    return $obj->{'size'};
};

local *update_local_info = sub {
    my $collection = shift;
    foreach(@$collection) {
        $obj = $_;
        next unless (length $obj->{'id'} > 0);
        if (!$local_collection{$obj->{'id'}}) {
            my %speeds = (
                'speeds' => [normalize($obj->{'speed'})],
                'seed_time' => $obj->{'seed_time'},
                'ratio' => $obj->{'ratio'},
                'file_size' => normalize_size($obj->{'file_size'}),
                'downloaded' => normalize_size($obj->{'downloaded'}),
                'tracker_status' => $obj->{'tracker_status'},
            );
            $local_collection{$obj->{'id'}} = \%speeds;
            next;
        }
        push @{$local_collection{$obj->{'id'}}->{'speeds'}}, normalize($obj->{'speed'});
        $local_collection{$obj->{'id'}}->{'seed_time'} = $obj->{'seed_time'};
        $local_collection{$obj->{'id'}}->{'ratio'} = $obj->{'ratio'};
        $local_collection{$obj->{'id'}}->{'file_size'} = normalize_size($obj->{'file_size'}); 
        $local_collection{$obj->{'id'}}->{'downloaded'} = normalize_size($obj->{'downloaded'});
        $local_collection{$obj->{'id'}}->{'tracker_status'} = $obj->{'tracker_status'};
    }
};

local *get_average = sub {
    my $objs = shift;
    my $total;
    my $n = 0;
    foreach(@$objs) {
        $total += $_;
        $n++;
    }
    return ($total/$n, $n);
};

local *get_slow_torrents = sub {
    my @slow;
    foreach(keys %local_collection) {
        my ($average, $n) = get_average($local_collection{$_}->{'speeds'}); # Average upload speed (MiB/s)
        my $upload_speed = $local_collection{$_}->{'speeds'}[-1];           # Real-time upload speed (MiB/s)         
        my $seeding_time = $local_collection{$_}->{'seed_time'};            # Seeding Time (hours)
        my $ratio_now = $local_collection{$_}->{'ratio'}; 
        my $data_size = $local_collection{$_}->{'file_size'};               # File Size (GiB)
        my $downloaded = $local_collection{$_}->{'downloaded'};             # Downloaded (GiB)
        my $host_name = $local_collection{$_}->{'tracker_status'};
        
        if ($save_log ==1){
            open(W, ">> AutoRemove.log") || die "$!\n";
            print W "n=$n thr=$thr upload_speed=$upload_speed seeding_time=$seeding_time ratio_now=$ratio_now $host_name\n";
            close(W);
        }
        
        ####################################################################################################################################
        my $HR = 0;       # Hit&Run time
        
        if ($host_name =~ /ABC/i) {
            if   ($data_size < 10){$HR =  72;}
            elsif($data_size > 86){$HR = 504;}
            else {$HR = 72 + 5 * ($data_size - 10);}
        }
        
        # AVI
        if ($host_name =~ /(AVI)/i) {
            $HR = 24 + $data_size / 5 ;
        }
        
        # CAZ H&R system
        if ($host_name =~ /(CAZ)/i) {
            if   ($data_size < 50){$HR =  72 + 2 * $data_size;}
            else {$HR = 100 * log($data_size) - 219.2023;} # 100*ln(x)-219.2023
        }
        
        if ((($n >= 999) && (                                                                                             # $seeding_time > 1 (Min seeding_time = 1 Period time)
        ($upload_speed < $thr && $seeding_time >=  0 && $ratio_now >= 0.0 && $host_name =~ /UU.+Announce.+OK$/i)       || # UU  : None
        ($upload_speed < $thr && $seeding_time >  36 && $ratio_now >= 0.0 && $host_name =~ /CD.+Announce.+OK$/i)       || # CD  : Seed > 36hours
        ($upload_speed < $thr && ($seeding_time >  48 || $ratio_now >  1.0) && $host_name =~ /TPT.+Ann.+OK$/i)         || # TPT : Seed > 48hour or Ratio > 1.0
        ($upload_speed < $thr && ($seeding_time > $HR || $ratio_now >  0.9) && $host_name =~ /AVI.+Announce.+OK$/i)    || # AVI : Seed 24~hours or Ratio > 0.9
        ($upload_speed < $thr && ($seeding_time > $HR || $ratio_now >  0.9) && $host_name =~ /CAZ.+Announce.+OK$/i)    || # CAZ : Seed 24~hours or Ratio > 0.9 (now H&R system)
        ($upload_speed < $thr && ($seeding_time > $HR || $ratio_now >  1.0) && $host_name =~ /ABC.+Announce.+OK$/i)    || # ABC : Seed 72~504hours or Ratio > 1.0
        ($upload_speed < $thr && $seeding_time > 3 && ( $seeding_time > 48 || $ratio_now > 1.0) && $host_name =~ /XXX.+Ann.+OK$/i))) # XXX   : Seed > 48hour or (Ratio > 1.0 & Seed > 3hour)
        || ($host_name =~ /.+not.+registered|.+unregistered/i))
        ####################################################################################################################################
        {
            push @slow, $_;
            delete $local_collection{$_};
        }
    }
    return \@slow;
};

while (true) {
    if ($save_log ==1){
        open(W, ">> AutoRemove.log") || die "$!\n";
        my $check = localtime();
        print W "Time: $check\n";
    }

    my $usage = `du -ms -B G $data_path`;
    $usage =~ /(\d+)/;
    my $disk_usage = $1;
    my $disk_space = $disk_space_MAX - $disk_usage;
    my $disk_space_per = $disk_space * 100 / $disk_space_MAX;
    
    $thr = -1.0;
    if (($disk_space_per <= $disk_threshold_per) || ($disk_space <= $disk_threshold_MB)){
        use List::Util qw/max min/;
        my @ratio_array = (abs($disk_threshold_per / $disk_space_per ), abs($disk_threshold_MB / $disk_space));
        my $max_ratio = max @ratio_array;
        my @thr_array = ($max_ratio, 5.0); # Maximum Upload speed threshold (5.0 MiB/s)
        my $thr_scale = min @thr_array; 
        $thr = (1.5 ** $thr_scale) - 1.499; # 1.5^(disk_space/disk_threshold) - 1.499
                                            # 剩餘空間: 設定門檻   => 刪除上傳低於 0.00 MiB/s 的種子
                                            # 剩餘空間: 設定門檻/2 => 刪除上傳低於 0.75 MiB/s 的種子
                                            # 剩餘空間: 設定門檻/4 => 刪除上傳低於 3.56 MiB/s 的種子
                                            # 剩餘空間: 設定門檻/8 => 刪除上傳低於 5.00 MiB/s 的種子
    }
    
    my $collection = get_deluge_info();
    if ($collection) {
        update_local_info($collection);
        #use Data::Dumper;
        #print Dumper($collection);
    }
    my $delete_list = get_slow_torrents();
    foreach(@$delete_list) {
        my $Time_del = localtime();
        print "($Time_del) Deleting $_ (Threshold $thr MiB/s)\n";
        my $output = `deluge-console "connect 127.0.0.1:$port; rm $_ --remove_data"`;
    }
    my $now_time = time();
    my $next_time = $now_time + $Period_min * 60;
    my $next_timestring = localtime($next_time);
    print "Next Inspection:  $next_timestring\n";
    sleep $Period_min * 60; # Period: X minutes
}
