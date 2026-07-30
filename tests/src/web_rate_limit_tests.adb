with AUnit.Assertions; use AUnit.Assertions;
with AUnit.Test_Caller;
with Web.Rate_Limit;

package body Web_Rate_Limit_Tests is

   --  One request; returns whether it was allowed.
   function Hit
     (Client : String; Now : Web.Rate_Limit.Timestamp) return Boolean
   is
      Allowed : Boolean;
      Retry   : Natural;
   begin
      Web.Rate_Limit.Check (Client, Now, Allowed, Retry);
      return Allowed;
   end Hit;

   procedure Test_Under_Limit (T : in out Fixture) is
      pragma Unreferenced (T);
   begin
      Web.Rate_Limit.Configure (Max_Requests => 3, Window_Seconds => 60);
      Assert (Hit ("rl-a", 100), "1st allowed");
      Assert (Hit ("rl-a", 100), "2nd allowed");
      Assert (Hit ("rl-a", 100), "3rd allowed");
   end Test_Under_Limit;

   procedure Test_Over_Limit (T : in out Fixture) is
      pragma Unreferenced (T);
      Allowed : Boolean;
      Retry   : Natural;
   begin
      Web.Rate_Limit.Configure (Max_Requests => 2, Window_Seconds => 60);
      Assert (Hit ("rl-b", 1000), "1st allowed");
      Assert (Hit ("rl-b", 1000), "2nd allowed");
      Web.Rate_Limit.Check ("rl-b", 1010, Allowed, Retry);
      Assert (not Allowed, "3rd refused");
      Assert (Retry = 50, "retry-after is seconds to window end:" & Retry'Image);
   end Test_Over_Limit;

   procedure Test_Window_Reset (T : in out Fixture) is
      pragma Unreferenced (T);
   begin
      Web.Rate_Limit.Configure (Max_Requests => 1, Window_Seconds => 60);
      Assert (Hit ("rl-c", 0), "allowed in window 1");
      Assert (not Hit ("rl-c", 30), "refused still in window 1");
      Assert (Hit ("rl-c", 60), "allowed once window elapses");
      Assert (not Hit ("rl-c", 90), "refused in window 2");
   end Test_Window_Reset;

   procedure Test_Per_Client (T : in out Fixture) is
      pragma Unreferenced (T);
   begin
      Web.Rate_Limit.Configure (Max_Requests => 1, Window_Seconds => 60);
      Assert (Hit ("rl-x", 0), "client x allowed");
      Assert (not Hit ("rl-x", 0), "client x refused");
      Assert (Hit ("rl-y", 0), "client y independent, allowed");
   end Test_Per_Client;

   procedure Test_Disabled (T : in out Fixture) is
      pragma Unreferenced (T);
   begin
      Web.Rate_Limit.Configure (Max_Requests => 0, Window_Seconds => 60);
      for I in 1 .. 100 loop
         Assert (Hit ("rl-z", 0), "disabled: everything allowed");
      end loop;
   end Test_Disabled;

   package Caller is new AUnit.Test_Caller (Fixture);

   procedure Add_Tests (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      Suite.Add_Test (Caller.Create ("RateLimit: under limit", Test_Under_Limit'Access));
      Suite.Add_Test (Caller.Create ("RateLimit: over limit + retry-after", Test_Over_Limit'Access));
      Suite.Add_Test (Caller.Create ("RateLimit: window reset", Test_Window_Reset'Access));
      Suite.Add_Test (Caller.Create ("RateLimit: per client", Test_Per_Client'Access));
      Suite.Add_Test (Caller.Create ("RateLimit: disabled", Test_Disabled'Access));
   end Add_Tests;

end Web_Rate_Limit_Tests;
