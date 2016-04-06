metadata    :name        => "Version",
            :description => "Checks package version",
            :author      => "Mirantis Inc",
            :license     => "Apache License 2.0",
            :version     => "10.0.0",
            :url         => 'http://www.mirantis.com/',
            :timeout     => 60

action "get_version", :description => "Get the version" do
    display :always
    output  :version,
            :description => "Version",
            :display_as => "Version"
end

