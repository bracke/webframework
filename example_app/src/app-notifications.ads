with Ada.Strings.Unbounded;

--  App.Notifications -- the example app's email-notification feature. It owns a
--  fully composed notifications Services.Engine wired to deliver an "email.demo"
--  notification through the notifications_templates renderer and the
--  notifications_email provider, over smtplib, to the in-process SMTP catcher
--  (App.Smtp_Catcher) on 127.0.0.1.
--
--  This concentrates all notifications wiring: a heap-allocated in-memory store,
--  a real system clock, a monotonic id source, a recipient resolver that turns
--  the caller-supplied target address into a single email destination, a
--  template-backed renderer with one registered email kind, and the smtplib
--  email provider over a plaintext, no-auth, localhost configuration. The page
--  handlers in App.Pages stay thin: they call Send and read the catcher.
package App.Notifications is

   use Ada.Strings.Unbounded;

   type Init_Status is
     (Ready, Store_Error, Kind_Register_Error, Kind_Finalize_Error,
      Renderer_Error, Config_Error);

   --  Compose the engine and its dependencies. Idempotent per process.
   procedure Initialize (Status : out Init_Status);

   --  What one Send did, for the demo page.
   type Send_Phase is
     (Not_Started,        --  Initialize never ran / failed
      Built,              --  the intent was created (before drive)
      Create_Rejected,    --  Services.Create refused the intent
      Delivered_Attempt,  --  create + drive ran; see the fields below
      Send_Error);        --  a contained internal fault

   type Send_Result is record
      Phase              : Send_Phase := Not_Started;
      Created            : Boolean := False;
      Reached_Catcher    : Boolean := False;  --  the catcher captured a new mail
      Provider_Called    : Boolean := False;
      Steps_Run          : Natural := 0;
      Create_Image       : Unbounded_String := Null_Unbounded_String;
      Provider_Class     : Unbounded_String := Null_Unbounded_String;
      Provider_Certainty : Unbounded_String := Null_Unbounded_String;
   end record;

   --  Build an "email.demo" notification addressed to To_Email, carrying Subject
   --  and Message in the payload, then create and synchronously drive it: this
   --  renders the email and delivers it through notifications_email -> smtplib ->
   --  a real socket -> the catcher. Never raises into the caller.
   procedure Send
     (To_Email : String;
      Subject  : String;
      Message  : String;
      Result   : out Send_Result);

   --  The result of the most recent Send (for the demo page after a redirect).
   function Last_Send return Send_Result;

end App.Notifications;
