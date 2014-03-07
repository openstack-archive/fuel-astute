metadata    :name        => "Network Probe Agent",
            :description => "Check network connectivity between nodes.",
            :author      => "Andrey Danin",
            :license     => "MIT",
            :version     => "0.1",
            :url         => "http://mirantis.com",
            :timeout     => 120

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

    input :nodes,
          :prompt         => "Multicat config for each node",
          :type           => :string,

    output :stdout,
           :description => "Output from multicast listen",
           :display_as => "Output"

    output :stderr,
           :description => "Stderr from multicast listen",
           :display_as => "Stderr"

    output :exit_code,
           :description => "Exit code of multicast listen",
           :display_as => "Exit code"
end

action "multicast_send", :description => "Send multicast frames" do
    display :always

    output :stdout,
           :description => "Output from multicast send",
           :display_as => "Output"

    output :stderr,
           :description => "Stderr from multicast send",
           :display_as => "Stderr"

    output :exit_code,
           :description => "Exit code of multicast send",
           :display_as => "Exit code"
end

action "multicast_info", :description => "Request received data from multicast frames" do
    display :always

    output :stdout,
           :description => "Output from multicast info",
           :display_as => "Output"

    output :stderr,
           :description => "Stderr from multicast info",
           :display_as => "Stderr"

    output :exit_code,
           :description => "Exit code of multicast info",
           :display_as => "Exit code"
end
