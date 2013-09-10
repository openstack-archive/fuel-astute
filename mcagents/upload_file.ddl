metadata  :name           => "upload_file",
		      :description    => "File upload agent",
		      :author         => "Mirantis Inc",
		      :license        => "Apache License 2.0",
		      :version        => "0.1",
		      :url            => "http://mirantis.com",
		      :timeout        => 60

action "upload",	:description => "upload file" do
	display :failed

  input :path,
        :prompt      => "Path to save file",
        :description => "Where should file be saved?",
        :type        => :string,
        :validation  => '^.+$',
        :optional    => false,
        :maxlength   => 256

  input :content,
        :prompt      => "File content",
        :description => "What should be contained in file?",
        :type        => :string,
        :optional    => false,
        :maxlength   => 0

  input :overwrite,
        :prompt      => "Force overwrite",
        :description => "Overwrite already existed file?",
        :type        => :boolean,
        :optional    => false,
        :default     => false
    
  input :parents,
        :prompt      => "Create intermediate directories as required",
        :description => "no error if destination directory existing, make parent directories as needed",
        :type        => :boolean,
        :optional    => false,
        :default     => true  

  output :msg,
         :description => "Report message",
         :display_as  => "Message"

end