metadata    :name        => "puppetd",
            :description => "Run puppet, get its status, and enable/disable it",
            :author      => "R.I.Pienaar",
            :license     => "Apache License 2.0",
            :version     => "1.8",
            :url         => "https://github.com/puppetlabs/mcollective-plugins",
            :timeout     => 40

action "last_run_summary", :description => "Get a summary of the last puppet run" do
    display :always

    output :time,
           :description => "Time per resource type",
           :display_as => "Times"
    output :resources,
           :description => "Overall resource counts",
           :display_as => "Resources"

    output :changes,
           :description => "Number of changes",
           :display_as => "Changes"

    output :events,
           :description => "Number of events",
           :display_as => "Events"

    output :version,
           :description => "Puppet and Catalog versions",
           :display_as => "Versions"
end

action "stop_and_disable", :description => "Stop and disable puppet" do
    output :output,
           :description => "String indicating status",
           :display_as => "Status"
end

action "enable", :description => "Enable puppet" do
    output :output,
           :description => "String indicating status",
           :display_as => "Status"
end

action "disable", :description => "Disable puppet" do
    output :output,
           :description => "String indicating status",
           :display_as => "Status"
end

action "runonce", :description => "Invoke a single puppet run" do

    input :manifest,
          :prompt         => "Path to manifest",
          :description    => "Path to manifest (relative or absolutely)",
          :type           => :string,
          :validation     => :shellsafe,
          :optional       => true,
          :default        => '/etc/puppet/manifests/site.pp',
          :maxlength      => 0

    input :modules,
          :prompt         => "Path to modules folder",
          :description    => "Path to modules folder (relative or absolutely)",
          :type           => :string,
          :validation     => :shellsafe,
          :optional       => true,
          :default        => '/etc/puppet/modules',
          :maxlength      => 0

    input :cwd,
          :prompt         => "CWD",
          :description    => "Path to folder where command will be run",
          :type           => :string,
          :validation     => :shellsafe,
          :optional       => true,
          :default        => '/tmp',
          :maxlength      => 0

    input :puppet_debug,
          :prompt      => "Puppet debug",
          :description => "Puppet run mode: debug",
          :type        => :boolean,
          :validation  => :typecheck,
          :default     => true,
          :optional    => true

    output :output,
           :description => "Output from puppet",
           :display_as => "Output"
end

action "status", :description => "Get puppet status" do
    display :always

    output :status,
           :description => "The status of the puppet: disabled, running, idling or stopped",
           :display_as => "Status"

    output :enabled,
           :description => "Whether puppet is enabled",
           :display_as => "Enabled"

    output :running,
           :description => "Whether puppet is running",
           :display_as => "Running"

    output :idling,
           :description => "Whether puppet is idling",
           :display_as => "Idling"

    output :stopped,
           :description => "Whether puppet is stopped",
           :display_as => "Stopped"

    output :lastrun,
           :description => "When puppet last ran",
           :display_as => "Last Run"

    output :output,
           :description => "String displaying puppet status",
           :display_as => "Status"
end
