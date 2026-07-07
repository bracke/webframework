package Webframework_Cli is
   --  Execute the CLI with Ada.Command_Line arguments.
   --  @return Process exit status code. 0 success, 1 runtime failure, 2 usage.
   function Run return Natural;
end Webframework_Cli;
