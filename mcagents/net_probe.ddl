metadata    :name        => "Network Probe Agent",
            :description => "Check network connectivity between nodes.",
            :author      => "Andrey Danin",
            :license     => "MIT",
            :version     => "6.0.0",
            :url         => "http://mirantis.com",
            :timeout     => 240

action "start_frame_listeners", :description => "Starts catching packets on interfaces" do
    display :always
end

action "send_probing_frames", :description => "Sends packets with VLAN tags" do
    display :always
end

action "get_probing_info", :description => "Get info about packets catched" do
    display :always
end

action "stop_frame_listeners", :description => "Stop catching packets, dump data to file" do
    display :always
end

action "echo", :description => "Silly echo" do
    display :always
end

action "dhcp_discover", :description => "Find dhcp server for provided interfaces" do
    display :always
end

action "multicast_listen", :description => "Start multicast listeners" do
    display :always
end

action "multicast_send", :description => "Send multicast frames" do
    display :always
end

action "multicast_info", :description => "Request received data from multicast frames" do
    display :always
end
