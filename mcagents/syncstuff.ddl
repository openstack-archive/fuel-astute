metadata:name             => "stuffsync",
          :description    => "Sync latest version of source to managed servers",
          :author         => "Mirantis Inc",
          :license        => "Apache License 2.0",
          :version        => "0.1",
          :url            => "http://mirantis.com",
          :timeout        => 300

action "rsync", :description => "Download using rsync" do
  display :failed

  input :source,
        :prompt      => "Rsync source URL",
        :description => "Where to get files from. URL with any protocol supported by rsync",
        :type        => :string,
        :validation  => :shellsafe,
        :optional    => false,
        :default     => 'rsync://10.20.0.2:/puppet/tasks/',
        :maxlength   => 256

  input :path,
        :prompt      => "Rsync destination",
        :description => "Where should downloaded modules be saved?",
        :type        => :string,
        :validation  => :shellsafe,
        :optional    => false,
        :default     => '/etc/puppet/modules/',
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