metadata:name             => "puppetsync",
          :description    => "Downloads latest version of Puppet manifests to managed servers",
          :author         => "Mirantis Inc",
          :license        => "Apache License 2.0",
          :version        => "6.0.0",
          :url            => "http://mirantis.com",
          :timeout        => 300

action "rsync", :description => "Download using rsync" do
  display :failed

  input :modules_source,
        :prompt      => "Rsync source URL of modules",
        :description => "Where to get modules from. URL with any protocol supported by rsync",
        :type        => :string,
        :validation  => :shellsafe,
        :optional    => false,
        :default     => 'rsync://10.20.0.2:/puppet/modules/',
        :maxlength   => 256

  input :manifests_source,
        :prompt      => "Rsync source URL of manifests",
        :description => "Where to get manifests from. URL with any protocol supported by rsync",
        :type        => :string,
        :validation  => :shellsafe,
        :optional    => false,
        :default     => 'rsync://10.20.0.2:/puppet/manifests/',
        :maxlength   => 256

  input :modules_path,
        :prompt      => "Rsync destination of modules",
        :description => "Where should downloaded modules be saved?",
        :type        => :string,
        :validation  => :shellsafe,
        :optional    => false,
        :default     => '/etc/puppet/modules/',
        :maxlength   => 256

  input :manifests_path,
        :prompt      => "Rsync destination of manifests",
        :description => "Where should downloaded manifests be saved?",
        :type        => :string,
        :validation  => :shellsafe,
        :optional    => false,
        :default     => '/etc/puppet/manifests/',
        :maxlength   => 256

  input :rsync_options,
        :prompt      => "Options for rsync command run",
        :description => "What options should be pathed to rsync command?",
        :type        => :string,
        :validation  => :shellsafe,
        :optional    => false,
        :default     => '-c -r --delete',
        :maxlength   => 256

  output :msg,
         :description => "Report message",
         :display_as  => "Message"

end
