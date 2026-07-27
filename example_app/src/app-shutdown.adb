with Ada.Interrupts.Names;
with System;

package body App.Shutdown is

   --  Library-level protected object so it can carry interrupt handlers. The
   --  handler runs at interrupt priority and does the minimum safe thing --
   --  open a barrier -- while the actual stop (which does socket I/O) happens
   --  back in the main task that was waiting on Wait.
   --  Only SIGTERM is handled: it is the graceful-stop signal (`kill` default,
   --  docker stop, systemd, Kubernetes) and, unlike SIGINT, the GNAT runtime
   --  does not reserve it. SIGINT (Ctrl-C) is left to the runtime's default.
   protected Control is
      pragma Interrupt_Priority (System.Interrupt_Priority'Last);
      entry Wait;
   private
      procedure Handle;
      pragma Attach_Handler (Handle, Ada.Interrupts.Names.SIGTERM);
      Triggered : Boolean := False;
   end Control;

   protected body Control is
      entry Wait when Triggered is
      begin
         null;
      end Wait;

      procedure Handle is
      begin
         Triggered := True;
      end Handle;
   end Control;

   procedure Await_Stop is
   begin
      Control.Wait;
   end Await_Stop;

end App.Shutdown;
