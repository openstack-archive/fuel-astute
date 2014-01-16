metadata    :name        => "Execute shell command",
            :description => "Execute shell command",
            :author      => "Mirantis Inc.",
            :license     => "Apache License 2.0",
            :version     => "0.0.1",
            :url         => "http://mirantis.com",
            :timeout     => 3600

action "execute", :description => "Execute shell command" do

	input :cmd,
          :prompt         => "Shell command",
          :description    => "Shell command for running",
          :type           => :string,
          :validation	  => '.*',
          :optional       => false,
          :maxlength      => 0

    output :stdout,
           :description => "Output from #{:cmd}",
           :display_as => "Output"

    output :stderr,
           :description => "Stderr from #{:cmd}",
           :display_as => "Stderr"

    output :exit_code,
           :description => "Exit code of #{:cmd}",
           :display_as => "Exit code"
end
