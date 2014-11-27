metadata  :name        => "Erase node bootloader and reboot it",
          :description => "Erase node bootloader and reboot it.",
          :author      => "Andrey Danin",
          :license     => "MIT",
          :version     => "6.0.0",
          :url         => "http://mirantis.com",
          :timeout     => 40

action "erase_node", :description => "Zeroing of boot device" do
  display :always

  input :reboot,
        :prompt      => "Reboot",
        :description => "Reboot the node after erasing?",
        :type        => :boolean,
        :validation  => :typecheck,
        :default     => true,
        :optional    => false

  input :dry_run,
        :prompt      => "Dry run",
        :description => "Do not performing any real changes",
        :type        => :boolean,
        :validation  => :typecheck,
        :default     => false,
        :optional    => false

  output :status,
         :description => "Shell exit code",
         :display_as  => "Status"

  output :erased,
         :description => "Status of erase operation (boolean)",
         :display_as  => "Erased"

  output :rebooted,
         :description => "Status of reboot operation (boolean)",
         :display_as  => "Rebooted"

  output :error_msg,
         :description => "Error messages",
         :display_as  => "Errors"

  output :debug_msg,
         :description => "Debug messages",
         :display_as  => "Debug"

end

action "reboot_node", :description => "Reboot node" do
  display :always

  output :debug_msg,
         :description => "Debug messages",
         :display_as  => "Debug"
end
