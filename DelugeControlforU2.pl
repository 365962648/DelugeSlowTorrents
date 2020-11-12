#!/usr/local/bin/perl
# Source  : https://github.com/cxmplex/DelugeSlowTorrents
# Auther  : BlackMickey
# Version : 20201113 v2.6.7

############### 安裝與執行 ###############

# 安裝
# mv -f commands /usr/lib/python2.7/dist-packages/deluge-1.3.15-py2.7.egg/deluge/ui/console/commands
# 修改下方的參數設定

# 執行
# perl DelugeControlforU2.pl
# 建議搭配 screen 於後台執行

############### 參數設定 ###############

# 不進行控制的種子儲存路徑
$bypass_path = "/home/Other";

# 檢測週期 (Minutes) 建議使用1~3分鐘，過長過短都有可能有未知BUG。
$Period_min = 2;

# 伺服器最大上傳速度 (Mbps)
$NIC_UL = 940;

# U2單種最大上傳速度 (MiB/s) 避免小黑屋悲劇使用，如果不怕小黑屋，可以設為 -1 
$MAX_UL_MiBps = 500;

# U2最大有效上傳速度 (MiB/s)
$tracker_max_MiBps = 50;

# 是否保存紀錄供除錯使用
$save_log = 1;

# 除錯紀錄檔案路徑
$log_path = "/tmp/AutoRemove.log";

##########################################

$datestring = localtime();
$port_info = `grep '"daemon_port": [0-9]*' ~/.config/deluge/core.conf`;
$port_info =~ /(\d+)/;
$port = $1;
$NIC_MiBps = int($NIC_UL / 8);

if ($MAX_UL_MiBps > 0) {$MAX_UL_KiBps = $MAX_UL_MiBps * 1024;}
else {$MAX_UL_KiBps = -1;}

$deluge_ver = `deluge -v | grep deluge | awk -F ' ' '{print $2}'`; 
if ($deluge_ver =~ /(2\.[0-9]\.[0-9]+)/) {
    $info_ver = 2;
} else {
    $info_ver = 1;
}

print "Local time $datestring\n";
print "Deluge version   : $deluge_ver"; 
print "Period           : $Period_min minutes\n"; 
print "Bypass torrents  : $bypass_path\n";
print "Deluge port      : $port\n";
print "NIC speed        : $NIC_MiBps MiB/s\n";
if( $save_log == 1 ){
    print "Save log         : True\n";
}else{
    print "Save log         : False\n";
}
sleep 5;

open(W, ">> $log_path") || die "$!\n";
my $check = localtime();
print W "AutoRemove Restart! $check\n";
close(W);

##########################################
my %local_collection;

local *get_deluge_info = sub {
    my $info;
    if ($info_ver == 1) {
        $info = `deluge-console "connect 127.0.0.1:$port; info2"`; 
    } elsif ($info_ver == 2) {    
        $info = `deluge-console "connect 127.0.0.1:$port; info2 -v"`; 
    }
    
    my @collection;
    while ($info =~ /(?:Name:\s)(.+)\n(?:ID:\s)([a-z0-9]+)\n(?:State:\s)([a-z]+)(?:.+Down Speed:\s(.+))?\s(?:Up Speed:\s(.+))?\n(?:Max\sUp\/Down\sSpeed:\s(-?[\d]+).*\/(-?[\d]+).*)\n(?:Seeds:\s(.+)\s(?:Peers:\s)(.+)\s(?:Availability:\s)([\d\.]+).+\n)?(?:Size:\s)(.+)\s(?:Ratio:\s)(-?[\d\.]+)\s(?:Raw\(U\/D\/W\/T\):\s)(.+)\n(?:Seed time:\s)(.+)\s(?:Active:\s)(.+)\n(?:Save path:\s)(.+)\n(?:Tracker status:\s)(.+)\s(?:Next Announce:\s)([0-9]+)(?:\n(?:Progress:\s)(\d+))?/ig) {
        my %deluge_obj = (
            'name' => $1,
            'id' => $2,
            'state' => $3,
            'max_upload_speed' => $6,
            'max_download_speed' => $7,
            'seeds' => $8,
            'peers' => $9,
            'availability' => $10,
            'ratio' => $12,
            'seeding_time' => $14,
            'active_time' => $15,
            'save_path' => $16,
            'tracker_status' => $17,
            'next_announce' => $18,
        );
        
        my $down_speed = $4 || '0.0 KiB/s';
        my $up_speed = $5;
        my $size = $11;
        my $raw = $13;
        my $progress = $19 || '';
        
        # ignore incomplete
        next if ($deluge_obj{'save_path'} =~ /$bypass_path/i);
        
        # set active_time & seeding_time
        if ($info_ver == 1) {
            $deluge_obj{'seeding_time'} =~ /^(\d+)(?:\s[a-z]+\s)(\d+):(\d+):(\d+)/i;
            $deluge_obj{'seeding_time'} = $1 * 24 + $2;
            $deluge_obj{'active_time'} =~ /^(\d+)(?:\s[a-z]+\s)(\d+):(\d+):(\d+)/i;
            $deluge_obj{'active_time'} = $1 * 24 + $2;
        } else { # $info_ver == 2
            $deluge_obj{'seeding_time'} =~ /^(\d+)?(?:[w]+\s)?(\d+)(?:[d]+\s)(\d+)(?:[h]+\s)/i;
            $deluge_obj{'seeding_time'} = $1 * 7 * 24 + $2 * 24 + $3;
            $deluge_obj{'active_time'} =~ /^(\d+)?(?:[w]+\s)?(\d+)(?:[d]+\s)(\d+)(?:[h]+\s)/i;
            $deluge_obj{'active_time'} = $1 * 7 * 24 + $2 * 24 + $3;
        }
        
        # set Speed
        $down_speed =~ /([\d\.]+)\s([a-z]+)/i;
        my %speed = (
            'speed' => 0,
            'unit' => '',
        );
        $speed{'speed'} = $1;
        $speed{'unit'} = $2;
        $deluge_obj{'download_rate'} = \%speed;
        
        $up_speed =~ /([\d\.]+)\s([a-z]+)/i;
        my %speed = (
            'speed' => 0,
            'unit' => '',
        );
        $speed{'speed'} = $1;
        $speed{'unit'} = $2;
        $deluge_obj{'upload_rate'} = \%speed;
        
        # set Uploaded & Downloaded & Size
        $raw =~ /([\d]+)\/([\d]+)\/([\d]+)\/([\d]+)/i;
        $deluge_obj{'uploaded'} = $1;
        $deluge_obj{'downloaded'} = $2;
        $deluge_obj{'total_wanted'} = $3;
        $deluge_obj{'total_size'} = $4;

        push @collection, \%deluge_obj;
    }
    return \@collection;
};

# normalize speed to a base unit of MiB/s
local *normalize = sub {
    my $obj = shift;
    if ($obj->{'unit'} =~ /K/i) {
        return $obj->{'speed'} /= 1024;
    }
    if ($obj->{'unit'} =~ /G/i) {
        return $obj->{'speed'} *= 1024;
    }
    return $obj->{'speed'};
};

local *update_local_info = sub {
    my $collection = shift;
    foreach(@$collection) {
        $obj = $_;
        next unless (length $obj->{'id'} > 0);
        if (!$local_collection{$obj->{'id'}}) {
            my %speeds = (
                'upload_rate' => [normalize($obj->{'upload_rate'})],
                'download_rate' => normalize($obj->{'download_rate'}),
                'name' => $obj->{'name'},
                'save_path' => $obj->{'save_path'},
                'seeding_time' => $obj->{'seeding_time'},
                'active_time' => $obj->{'active_time'},
                'ratio' => $obj->{'ratio'},
                'uploaded' => [$obj->{'uploaded'}],
                'downloaded' => [$obj->{'downloaded'}],
                'total_wanted' => $obj->{'total_wanted'},
                'total_size' => $obj->{'total_size'},
                'max_upload_speed' => $obj->{'max_upload_speed'},
                'max_download_speed' => $obj->{'max_download_speed'},
                'tracker_status' => $obj->{'tracker_status'},
                'next_announce' => $obj->{'next_announce'},
                'announce_period' => 1800,
                'state' => $obj->{'state'},
                'last_uploaded' => 0,
                'last_down' => 0,
            );
            
            if ($obj->{'tracker_status'} =~ /dmhy/i && $obj->{'next_announce'} > 2700 && $obj->{'next_announce'} <= 3600 && $speeds{'announce_period'} < 3600) {
                $speeds{'announce_period'} = 3600;
            } elsif ($obj->{'tracker_status'} =~ /dmhy/i && $obj->{'next_announce'} > 1800 && $obj->{'next_announce'} <= 2700 && $speeds{'announce_period'} < 2700) {
                $speeds{'announce_period'} = 2700;
            }
            
            $local_collection{$obj->{'id'}} = \%speeds;
            next;
        }
        push @{$local_collection{$obj->{'id'}}->{'upload_rate'}}, normalize($obj->{'upload_rate'});
        $local_collection{$obj->{'id'}}->{'download_rate'} = normalize($obj->{'download_rate'});
        $local_collection{$obj->{'id'}}->{'name'} = $obj->{'name'};
        $local_collection{$obj->{'id'}}->{'save_path'} = $obj->{'save_path'};
        $local_collection{$obj->{'id'}}->{'seeding_time'} = $obj->{'seeding_time'};
        $local_collection{$obj->{'id'}}->{'active_time'} = $obj->{'active_time'};
        $local_collection{$obj->{'id'}}->{'ratio'} = $obj->{'ratio'};
        push @{$local_collection{$obj->{'id'}}->{'uploaded'}}, $obj->{'uploaded'}; 
        push @{$local_collection{$obj->{'id'}}->{'downloaded'}}, $obj->{'downloaded'};
        $local_collection{$obj->{'id'}}->{'total_wanted'} = $obj->{'total_wanted'};
        $local_collection{$obj->{'id'}}->{'total_size'} = $obj->{'total_size'};
        $local_collection{$obj->{'id'}}->{'max_upload_speed'} = $obj->{'max_upload_speed'};
        $local_collection{$obj->{'id'}}->{'max_download_speed'} = $obj->{'max_download_speed'};
        $local_collection{$obj->{'id'}}->{'tracker_status'} = $obj->{'tracker_status'};
        $local_collection{$obj->{'id'}}->{'next_announce'} = $obj->{'next_announce'};
        $local_collection{$obj->{'id'}}->{'state'} = $obj->{'state'};
        
        if ($obj->{'next_announce'} <= 0 || $obj->{'next_announce'} > 7200) {
            $local_collection{$obj->{'id'}}->{'next_announce'} = $local_collection{$obj->{'id'}}->{'announce_period'};
        }
        
        if ($obj->{'next_announce'} > 2700 && $obj->{'next_announce'} <= 3600 && $local_collection{$obj->{'id'}}->{'announce_period'} < 3600) {
            $local_collection{$obj->{'id'}}->{'announce_period'} = 3600;
        } elsif ($obj->{'next_announce'} > 1800 && $obj->{'next_announce'} <= 2700 && $local_collection{$obj->{'id'}}->{'announce_period'} < 2700) {
            $local_collection{$obj->{'id'}}->{'announce_period'} = 2700;
        }

        if ($obj->{'next_announce'} > ($local_collection{$obj->{'id'}}->{'announce_period'} - ($Period_min * 60 + 12))) {
            $local_collection{$obj->{'id'}}->{'last_uploaded'} = $local_collection{$obj->{'id'}}->{'uploaded'}[-2];
            $local_collection{$obj->{'id'}}->{'last_down'} = $local_collection{$obj->{'id'}}->{'downloaded'}[-2];
        }
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
        my ($average, $n) = get_average($local_collection{$_}->{'upload_rate'}); # Average upload speed (MiB/s)
        my $upload_rate = $local_collection{$_}->{'upload_rate'}[-1];            # Real-time upload speed (MiB/s)  
        my $download_rate = $local_collection{$_}->{'download_rate'};            # Real-time download speed (MiB/s)  
        my $torrent_name = $local_collection{$_}->{'name'};                      # Torrent name  
        my $save_path = $local_collection{$_}->{'save_path'};                    # Torrent save path         
        my $seeding_time = $local_collection{$_}->{'seeding_time'};              # Seeding Time (hours)
        my $active = $local_collection{$_}->{'active_time'};                     # Active Time (hours)
        my $ratio = $local_collection{$_}->{'ratio'};                            # Uploaded-Downloaded Ratio
        my $total_wanted_b = $local_collection{$_}->{'total_wanted'};            # Wanted Size (Byte)
        my $total_wanted = $total_wanted_b / 1073741824;                         # Wanted Size (GiB)
        my $data_size_b = $local_collection{$_}->{'total_size'};                 # File Size (Byte)
        my $data_size = $data_size_b / 1073741824;                               # File Size (GiB)
        my $uploaded_b = $local_collection{$_}->{'uploaded'}[-1];                # Uploaded (Byte)
        my $uploaded = $uploaded_b / 1073741824;                                 # Uploaded (GiB)
        my $downloaded_b = $local_collection{$_}->{'downloaded'}[-1];            # Downloaded (Byte)
        my $host_name = $local_collection{$_}->{'tracker_status'};               # Tracker
        my $next_announce = $local_collection{$_}->{'next_announce'};            # Next announce (Sec)
        my $max_upload_speed = $local_collection{$_}->{'max_upload_speed'};      # Max upload speed (KiB/s)
        my $max_download_speed = $local_collection{$_}->{'max_download_speed'};  # Max download speed (KiB/s)
        my $state = $local_collection{$_}->{'state'};
        my $last_uploaded_b = $local_collection{$_}->{'last_uploaded'};
        my $last_down_b = $local_collection{$_}->{'last_down'};
        my $announce_period = $local_collection{$_}->{'announce_period'};

        # U2區間控速系統
        if ($host_name =~ /(dmhy)/i && $uploaded_b > 0 && $average > 0) {
            my $uploaded_b_last;
            my $downloaded_b_last;
            my $interval_DL_b;
            my $avg_DL_b;
            my $eta;
            my $announce_uploaded_max_b;
            my $brake;
            my $DL_control;
            
            if ($#{$local_collection{$_}->{'uploaded'}} > 0) {
                $uploaded_b_last = $local_collection{$_}->{'uploaded'}[-2];
                $downloaded_b_last = $local_collection{$_}->{'downloaded'}[-2];
            } else {
                $uploaded_b_last = 0;
                $downloaded_b_last = 0;
            }
            
            # 週期內上傳速度
            my $interval_UL_b = abs(($uploaded_b - $uploaded_b_last) / ($Period_min * 60));
            my $avg_UL_b;
            if (($announce_period - $next_announce) < ($Period_min * 60)) {       # 修正剛匯報BUG
                $avg_UL_b = $interval_UL_b;  
            } else {
                $avg_UL_b = abs(($uploaded_b - $last_uploaded_b) / ($announce_period - $next_announce + 0.1)); # 防止除0導致錯誤
            }
            
            # ETA
            if ($state =~ /(Downloading)/i) {
                $interval_DL_b = abs(($downloaded_b - $downloaded_b_last) / ($Period_min * 60));
                $avg_DL_b = abs(($downloaded_b - $last_down_b) / ($announce_period - $next_announce + 0.1));
                my $eta_mode1 = abs(($total_wanted_b - $downloaded_b) / ($download_rate * 1048576 + 0.1)); 
                my $eta_mode2 = abs(($total_wanted_b - $downloaded_b) / ($interval_DL_b + 0.1));           
                my $eta_mode3;
                if (($announce_period - $next_announce) < ($Period_min * 60)) {                            # 修正剛匯報BUG
                    $eta_mode3 = $eta_mode2;
                } else {
                    $eta_mode3 = abs(($total_wanted_b - $downloaded_b) / ($avg_DL_b + 0.1)); 
                }
                use List::Util qw/max min/;
                my @ETA_array = (int($eta_mode1), int($eta_mode2), int($eta_mode3));
                $eta = min @ETA_array;
            # Seeding
            } else {
                $interval_DL_b = 0;
                $eta = $announce_period;
            }

            # 排除低速種子
            if ($interval_UL_b > 5242880 || $avg_UL_b > 5242880 || $interval_DL_b > 5242880 || $eta < $announce_period || $max_upload_speed > -1) {

                # 延後完成控制系統，只適合超高速種，而且種子體積大的，U2人人刷神，不適合使用。
                $DL_control_system = 0;
                if ($DL_control_system == 1 && $eta < $next_announce && $next_announce > 30 && $avg_UL_b > $tracker_max_MiBps * 1048576 * 0.95) {  # 只考慮高速種 來不及壓低至47.5MiB/s的種子
                    $eta_cal = $eta;
                    $eta = $next_announce - 20;
                    
                    if ($eta_cal < ($Period_min * 60 + 10) && $n > 0) {   # 只在最後一次匯報時限制
                        my $DL_mode1 = int(($total_wanted_b - $downloaded_b) / $eta / 1024);                    # 預估最低下載速度 KiB/s
                        my $DL_mode2 = int(($total_wanted_b - $downloaded_b) / ($Period_min * 60 + 30) / 1024); # 預估最高下載速度 KiB/s
                        use List::Util qw/max min/;
                        my @DL_control_array = ($DL_mode1, $DL_mode2); # 減少抑制速度
                        $DL_control = max @DL_control_array;
                        my $U2_DL_control = `deluge-console "connect 127.0.0.1:$port; manage $_ --set=max_download_speed $DL_control"`;
                    }
                }
                
                # 下次匯報最大上傳量
                if ($eta < $next_announce) {
                    $announce_uploaded_max_b = ($announce_period - ($next_announce - $eta)) * $tracker_max_MiBps * 1048576;
                    $seed_announce = $eta;
                } else {
                    $announce_uploaded_max_b = $announce_period * $tracker_max_MiBps * 1048576;
                    $seed_announce = $next_announce;
                }
                my $announce_upload_avg_b = ($announce_uploaded_max_b - ($uploaded_b - $last_uploaded_b)) / ($seed_announce + 0.1); 
                my $announce_upload_avg = $announce_upload_avg_b / 1048576;
                
                # 計算控速區間
                my $limit_unlimit_t = int(($announce_period * $tracker_max_MiBps / $NIC_MiBps / $Period_min / 60) - 1) * $Period_min * 60; 
                my $limit_mode1_t = int(($announce_period - $unlimit_time) / $Period_min / 60 / 2) * $Period_min * 60; 
                my $limit_mode2_t = int($Period_min * 2.50) * 60;
                my $limit_mode3_t = int($Period_min * 1.25) * 60;
                
                # 如果區間速度大於最大平均速度，則進行限速
                if ($announce_upload_avg_b > 0) {
                    if ((($announce_uploaded_max_b - ($uploaded_b - $last_uploaded_b)) > $NIC_MiBps * $Period_min * 60 * 1.25 * 1048576 && $NIC_MiBps > 350) || # 當距離匯報極限1.25次時，不限速，10G機器可能不適合
                        (($announce_uploaded_max_b - ($uploaded_b - $last_uploaded_b)) > $NIC_MiBps * $Period_min * 60 * 2.50 * 1048576 && $NIC_MiBps <= 350)){ # 當距離匯報極限2.5次時，不限速，10G機器可能不適合
                        $brake = $MAX_UL_KiBps;
                        $bMode = 'unlimit_1';
                    } elsif ($seed_announce > $announce_period - $limit_unlimit_t) { 
                        $brake = $MAX_UL_KiBps;
                        $bMode = 'unlimit_2';
                    } elsif ($seed_announce > $announce_period - $limit_unlimit_t - $limit_mode1_t) {
                        $brake = int($announce_upload_avg_b / 1024 * 1.7);                            
                        $bMode = '1.70X';
                    } elsif ($seed_announce > $limit_mode2_t) {                              
                        $brake = int($announce_upload_avg_b / 1024 * 1.25); 
                        $bMode = '1.25X';
                    } elsif ($seed_announce <= $limit_mode3_t) {              
                        if ($announce_upload_avg > $tracker_max_MiBps && $seed_announce == $next_announce && $eta <= $seed_announce + $limit_mode3_t) {
                            $brake = int($tracker_max_MiBps * 1024 * 0.95);
                            $bMode = '0.75X_0.95X';
                        } else {
                            $brake = int($announce_upload_avg_b / 1024 * 0.75);
                            $bMode = '0.75X';
                        }
                    } elsif ($seed_announce <= $limit_mode2_t) {        
                        $brake = int($announce_upload_avg_b / 1024 * 0.9);
                        $bMode = '0.9X';
                    }# else {                                              
                    #    $brake = -1;
                    #}
                    
                    if ($DL_control_system == 1 && $avg_UL_b < ($tracker_max_MiBps * 1048576 * 0.95) && $state =~ /(Downloading)/i) {
                        my $U2_DL_control = `deluge-console "connect 127.0.0.1:$port; manage $_ --set=max_download_speed -1"`; 
                    }
 
                } else {
                    $brake = $tracker_max_MiBps * 1024; # 50MiB/s
                    $bMode = 'announce_upload < 0';
                    if ($info_ver == 1) {
                        my $U2_update = `deluge-console "connect 127.0.0.1:$port; update-tracker $_"`;
                    } else {
                        my $U2_update = `deluge-console "connect 127.0.0.1:$port; update_tracker $_"`;
                    }
                }
                
                # 出種後控速規則修改
                if ($state =~ /(Seeding)/i && ( $brake > 15360 || ((($announce_uploaded_max_b - ($uploaded_b - $last_uploaded_b))/1048576) > $NIC_MiBps * $Period_min * 60))) {
                    $brake = $MAX_UL_KiBps;
                    $bMode = 'Seeding';
                }
                
                if ($brake > $NIC_MiBps * 1024) {$brake = -1; $bMode = 'over speed';} 
                elsif ($brake > $MAX_UL_KiBps && $MAX_UL_KiBps > 0) {$brake = $MAX_UL_KiBps; $bMode = 'over MAX_UL_MiBps';} 
                elsif ($brake < 2097152) {$brake = $brake;} 
                else {$brake = 2097152 - 1;} # Deluge設定上限為2GiB/s
                
                if ($brake != $max_upload_speed) {
                    if ($info_ver == 1) {
                        my $U2_limit = `deluge-console "connect 127.0.0.1:$port; manage $_ --set=max_upload_speed $brake"`;
                    } else {
                        my $U2_limit = `deluge-console "connect 127.0.0.1:$port; manage $_ --set=max_upload_speed $brake"`;
                    }
                }
                
                if ($save_log == 1 && ($state =~ /(Downloading)/i || $brake != $max_upload_speed)) {
                    open(W, ">> $log_path") || die "$!\n";
                    printf W "Data size: %7.2f GiB / downloaded: %7.2f GiB / uploaded: %7.2f GiB / Last Up: %7.2f GiB / DL speed: %7.3f MiB/s / UL speed: %7.3f MiB/s\n", $data_size, $downloaded_b/1073741824, $uploaded, $last_uploaded_b/1073741824, $interval_DL_b/1048576, $interval_UL_b/1048576;
                    printf W "Next announce: %6.1f Sec / Seeding announce: %6.1f Sec / Max Uploaded(est): %7.2f GiB / Max UL Speed(est): %7.3f MiB/s / Setting UL/DL Speed: %7.3f / %7.3f MiB/s / Mode %s\n", $next_announce, $seed_announce, $announce_uploaded_max_b/1073741824, $announce_upload_avg, $brake/1024, $DL_control/1024 , $bMode;
                    close(W);
                }
            }
        }
    }
    return \@slow;
};

while (true) {
    $start_time = time();
    if ($save_log == 1) {
        open(W, ">> $log_path") || die "$!\n";
        my $check = localtime();
        print W "Time: $check\n";
        close(W);
    }

    my $collection = get_deluge_info();
    if ($collection) {
        update_local_info($collection);
        #use Data::Dumper;
        #print Dumper($collection);
    }

    my $delete_list = get_slow_torrents();
    
    if ($save_log == 1) {
        printf W "Waiting...";
        close(W);
    }
    
    my $next_timestring = localtime($start_time + $Period_min * 60);
    print "Next Inspection:  $next_timestring\n";
    my $sleep_time = int(($start_time + $Period_min * 60) - time());
    sleep $sleep_time; # Period: 2 minutes
}
