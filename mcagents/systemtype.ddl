metadata    :name        => "systemtype",
            :description => "Checks system type out of file",
            :author      => "Mirantis Inc",
            :license     => "Apache License 2.0",
            :version     => "6.0.0",
            :url         => 'http://www.mirantis.com/',
            :timeout     => 60

action "get_type", :description => "Get the type" do
    display :always
    output  :node_type,
            :description => "Type out of file",
            :display_as => "Node type"
end
