#
# Copyright 2016 Centreon (http://www.centreon.com/)
#
# Centreon is a full-fledged industry-strength solution that meets
# the needs in IT infrastructure and application monitoring for
# service performance.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

package network::cisco::prime::restapi::mode::apusage;

use base qw(centreon::plugins::templates::counter);

use strict;
use warnings;
use centreon::plugins::misc;
use centreon::plugins::statefile;

my $instance_mode;

sub custom_status_threshold {
    my ($self, %options) = @_; 
    my $status = 'ok';
    my $message;
    
    eval {
        local $SIG{__WARN__} = sub { $message = $_[0]; };
        local $SIG{__DIE__} = sub { $message = $_[0]; };
        
        if (defined($instance_mode->{option_results}->{critical_ap_status}) && $instance_mode->{option_results}->{critical_ap_status} ne '' &&
            eval "$instance_mode->{option_results}->{critical_ap_status}") {
            $status = 'critical';
        } elsif (defined($instance_mode->{option_results}->{warning_ap_status}) && $instance_mode->{option_results}->{warning_ap_status} ne '' &&
                 eval "$instance_mode->{option_results}->{warning_ap_status}") {
            $status = 'warning';
        }
    };
    if (defined($message)) {
        $self->{output}->output_add(long_msg => 'filter status issue: ' . $message);
    }

    return $status;
}

sub custom_status_output {
    my ($self, %options) = @_;
    my $msg = 'status : ' . $self->{result_values}->{status} . '(admin: ' . $self->{result_values}->{admin_status} . ')';

    return $msg;
}

sub custom_status_calc {
    my ($self, %options) = @_;
    
    $self->{result_values}->{status} = $options{new_datas}->{$self->{instance} . '_status'};
    $self->{result_values}->{name} = $options{new_datas}->{$self->{instance} . '_name'};
    $self->{result_values}->{controller} = $options{new_datas}->{$self->{instance} . '_controller'};
    $self->{result_values}->{admin_status} = $options{new_datas}->{$self->{instance} . '_admin_status'};
    
    return 0;
}

sub custom_uptime_output {
    my ($self, %options) = @_;
    my $msg = 'uptime started since : ' . centreon::plugins::misc::change_seconds(value => $self->{result_values}->{uptime});

    return $msg;
}

sub custom_lwappuptime_output {
    my ($self, %options) = @_;
    my $msg = 'uptime started since : ' . centreon::plugins::misc::change_seconds(value => $self->{result_values}->{lwapp_uptime});

    return $msg;
}

sub set_counters {
    my ($self, %options) = @_;
    
    $self->{maps_counters_type} = [
        { name => 'ctrl', type => 1, cb_prefix_output => 'prefix_controller_output', message_multiple => 'All controllers are ok', , skipped_code => { -11 => 1 } },
        { name => 'ap', type => 1, cb_prefix_output => 'prefix_ap_output', message_multiple => 'All access points are ok', , skipped_code => { -11 => 1 } },
    ];
    
    $self->{maps_counters}->{ap} = [
        { label => 'ap-status', threshold => 0, set => {
                key_values => [ { name => 'status' }, { name => 'name' }, { name => 'controller' }, { name => 'admin_status' } ],
                closure_custom_calc => $self->can('custom_status_calc'),
                closure_custom_output => $self->can('custom_status_output'),
                closure_custom_perfdata => sub { return 0; },
                closure_custom_threshold_check => $self->can('custom_status_threshold'),
            }
        },
        { label => 'ap-clients', set => {
                key_values => [ { name => 'client_count' }, { name => 'name' } ],
                output_template => 'Clients : %s',
                perfdatas => [
                    { label => 'ap_clients', value => 'client_count_absolute', template => '%s',
                      min => 0, label_extra_instance => 1, instance_use => 'display_absolute' },
                ],
            }
        },
        { label => 'ap-uptime', set => {
                key_values => [ { name => 'uptime' }, { name => 'name' } ],
                closure_custom_output => $self->can('custom_uptime_output'),
                perfdatas => [
                    { label => 'ap_uptime', value => 'uptime_absolute', template => '%s',
                      min => 0, label_extra_instance => 1, instance_use => 'display_absolute' },
                ],
            }
        },
        { label => 'ap-lwappuptime', set => {
                key_values => [ { name => 'lwapp_uptime' }, { name => 'name' } ],
                closure_custom_output => $self->can('custom_lwappuptime_output'),
                perfdatas => [
                    { label => 'ap_lwappuptime', value => 'lwapp_uptime_absolute', template => '%s',
                      min => 0, label_extra_instance => 1, instance_use => 'display_absolute' },
                ],
            }
        },
    ];
    
    $self->{maps_counters}->{ctrl} = [
        { label => 'ctrl-ap-count', set => {
                key_values => [ { name => 'ap_count' }, { name => 'name' } ],
                output_template => 'Number of access points : %s',
                perfdatas => [
                    { label => 'ctrl_ap_count', value => 'ap_count_absolute', template => '%s',
                      min => 0, label_extra_instance => 1, instance_use => 'display_absolute' },
                ],
            }
        },
    ];
}

sub new {
    my ($class, %options) = @_;
    my $self = $class->SUPER::new(package => __PACKAGE__, %options);
    bless $self, $class;
    
    $self->{version} = '1.0';
    $options{options}->add_options(arguments =>
                                {
                                  "filter-controller:s"     => { name => 'filter_controller' },
                                  "filter-ap:s"             => { name => 'filter_ap' },
                                  "warning-ap-status:s"     => { name => 'warning_ap_status', default => '%{admin_status} =~ /enable/i && %{status} =~ /minor|warning/i' },
                                  "critical-ap-status:s"    => { name => 'critical_ap_status', default => '%{admin_status} =~ /enable/i && %{status} =~ /major|critical/i' },
                                  "reload-cache-time:s"     => { name => 'reload_cache_time', default => 180 },
                                });
    $self->{statefile_cache_ap} = centreon::plugins::statefile->new(%options);
   
    return $self;
}

sub check_options {
    my ($self, %options) = @_;
    $self->SUPER::check_options(%options);

    $self->{statefile_cache_ap}->check_options(%options);
    $instance_mode = $self;
    $self->change_macros();
}

sub prefix_controller_output {
    my ($self, %options) = @_;
    
    return "Controller '" . $options{instance_value}->{controllerName} . "' ";
}

sub prefix_ap_output {
    my ($self, %options) = @_;
    
    return "Access point '" . $options{instance_value}->{name} . "' ";
}

sub change_macros {
    my ($self, %options) = @_;
    
    foreach (('warning_ap_status', 'critical_ap_status')) {
        if (defined($self->{option_results}->{$_})) {
            $self->{option_results}->{$_} =~ s/%\{(.*?)\}/\$self->{result_values}->{$1}/g;
        }
    }
}

sub manage_selection {
    my ($self, %options) = @_;
 
    my $access_points = $options{custom}->cache_ap(statefile => $self->{statefile_cache_ap}, 
                                                   reload_cache_time => $self->{option_results}->{reload_cache_time});
                                                           
    ($self->{ap}, $self->{ctrl}) = ({}, {});
    
    foreach my $ap_name (keys %{$access_points}) {        
        if (defined($self->{option_results}->{filter_ap}) && $self->{option_results}->{filter_ap} ne '' &&
            $ap_name !~ /$self->{option_results}->{filter_ap}/) {
            $self->{output}->output_add(long_msg => "skipping  '" . $ap_name . "': no matching filter.", debug => 1);
            next;
        }
        if (defined($self->{option_results}->{filter_controller}) && $self->{option_results}->{filter_controller} ne '' &&
            $access_points->{$ap_name}->{controllerName} !~ /$self->{option_results}->{filter_controller}/) {
            $self->{output}->output_add(long_msg => "skipping  '" . $access_points->{$ap_name}->{controllerName} . "': no matching filter.", debug => 1);
            next;
        }

        $self->{ap}->{$ap_name} = { 
            name => $ap_name, controller => $access_points->{$ap_name}->{controllerName},
            status => $access_points->{$ap_name}->{status},
            admin_status => $access_points->{$ap_name}->{adminStatus},
            client_count => $access_points->{$ap_name}->{clientCount},
            lwapp_uptime => $access_points->{$ap_name}->{lwappUpTime},
            uptime => $access_points->{$ap_name}->{upTime},
        };
        $self->{ctrl}->{$access_points->{$ap_name}->{controllerName}} = { ap_count => 0 }
            if (!defined($self->{ctrl}->{$access_points->{$ap_name}->{controllerName}}));
        $self->{ctrl}->{$access_points->{$ap_name}->{controllerName}}->{ap_count}++;
    }
    
    if (scalar(keys %{$self->{ap}}) <= 0) {
        $self->{output}->add_option_msg(short_msg => "No AP found.");
        $self->{output}->option_exit();
    }
}

1;

__END__

=head1 MODE

Check AP usages (also the number of access points by controller).

=over 8

=item B<--filter-ap>

Filter ap name (can be a regexp).

=item B<--filter-controller>

Filter controller name (can be a regexp).

=item B<--filter-counters>

Only display some counters (regexp can be used).
Example: --filter-counters='^total-error$'

=item B<--warning-*>

Threshold warning.
Can be: 'total-error', 'total-running', 'total-unplanned',
'total-finished', 'total-coming'.

=item B<--critical-*>

Threshold critical.
Can be: 'total-error', 'total-running', 'total-unplanned',
'total-finished', 'total-coming'.

=item B<--warning-ap-status>

Set warning threshold for status (Default: '%{admin_status} =~ /enable/i && %{status} =~ /minor|warning/i')
Can used special variables like: %{name}, %{status}, %{controller}, %{admin_status}

=item B<--critical-ap-status>

Set critical threshold for status (Default: '%{admin_status} =~ /enable/i && %{status} =~ /major|critical/i').
Can used special variables like: %{name}, %{status}, %{controller}, %{admin_status}

=item B<--reload-cache-time>

Time in seconds before reloading cache file (default: 180).

=back

=cut
