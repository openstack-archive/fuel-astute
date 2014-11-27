metadata  :name           => "uploadfile",
		      :description    => "Text file upload agent",
		      :author         => "Mirantis Inc",
		      :license        => "Apache License 2.0",
		      :version        => "6.0.0",
		      :url            => "http://mirantis.com",
		      :timeout        => 60

action "upload",	:description => "upload file" do
	display :failed

  input :path,
        :prompt      => "Path to save text file",
        :description => "Where should file be saved?",
        :type        => :string,
        :validation  => :shellsafe,
        :optional    => false,
        :maxlength   => 256

  input :content,
        :prompt      => "File content",
        :description => "What should be contained in file?",
        :type        => :string,
        :validation  => '^.+$',
        :optional    => false,
        :maxlength   => 0
  
  input :user_owner,
        :prompt      => "User owner of file",
        :description => "Who should be owner of the file?",
        :type        => :string,
        :validation  => :shellsafe,
        :optional    => false,
        :default     => 'root',
        :maxlength   => 0

  input :group_owner,
        :prompt      => "Group owner of file",
        :description => "What group should be owner of the file?",
        :type        => :string,
        :validation  => :shellsafe,
        :optional    => false,
        :default     => 'root',
        :maxlength   => 0
  
  input :permissions,
        :prompt      => "File permissions",
        :description => "What permissions should be set to the file?",
        :type        => :string,
        :validation  => '^[0-7]{3,4}$',
        :default     => '0644',
        :optional    => false,
        :maxlength   => 4
  
  input :dir_permissions,
        :prompt      => "Directory permissions",
        :description => "What permissions should be set for folder where file will be place?",
        :type        => :string,
        :validation  => '^[0-7]{3,4}$',
        :optional    => true,
        :default     => '0755',
        :maxlength   => 4

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
