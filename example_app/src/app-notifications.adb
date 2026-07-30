with Ada.Calendar;
with Ada.Streams; use Ada.Streams;

with Notifications.Memory_Store;
with Notifications.Services;
with Notifications.Repositories;
with Notifications.Identifiers;
with Notifications.Id_Primitives;
with Notifications.Time;
with Notifications.Intents;
with Notifications.Kinds;
with Notifications.Payloads;
with Notifications.Payloads.Schema;
with Notifications.Values;
with Notifications.Classification;
with Notifications.Recipients;
with Notifications.Destinations;
with Notifications.Rendering;
with Notifications.Retries;
with Notifications.Providers;
with Notifications.Provider_Results;
with Notifications.Messages;

with Notifications_Templates;
with Notifications_Email;

with Smtplib;
with Smtplib.Configuration;
with Smtplib.Network;
with Smtplib.Backends.Default_Network;
with Smtplib.Backends.Default_Random;

with App.Smtp_Catcher;

package body App.Notifications is

   --  This unit is App.Notifications, so the simple name "Notifications" binds
   --  to it; the top-level library is reached via Standard.
   package MS   renames Standard.Notifications.Memory_Store;
   package Svc  renames Standard.Notifications.Services;
   package Rep  renames Standard.Notifications.Repositories;
   package Id   renames Standard.Notifications.Identifiers;
   package IP   renames Standard.Notifications.Id_Primitives;
   package Tm   renames Standard.Notifications.Time;
   package In_T renames Standard.Notifications.Intents;
   package K    renames Standard.Notifications.Kinds;
   package Pl   renames Standard.Notifications.Payloads;
   package Sc   renames Standard.Notifications.Payloads.Schema;
   package Val  renames Standard.Notifications.Values;
   package Cls  renames Standard.Notifications.Classification;
   package Rcp  renames Standard.Notifications.Recipients;
   package Dst  renames Standard.Notifications.Destinations;
   package Rd   renames Standard.Notifications.Rendering;
   package Rt   renames Standard.Notifications.Retries;
   package Pv   renames Standard.Notifications.Providers;
   package PR   renames Standard.Notifications.Provider_Results;
   package Msg  renames Standard.Notifications.Messages;
   package NT   renames Notifications_Templates;
   package NE   renames Notifications_Email;
   package Cfg  renames Smtplib.Configuration;
   package Net  renames Smtplib.Network;
   package DN   renames Smtplib.Backends.Default_Network;
   package DR   renames Smtplib.Backends.Default_Random;

   use type NT.Register_Outcome;
   use type In_T.Build_Outcome;
   use type Svc.Create_Result;

   Kind_Symbol : constant String := "email.demo";
   Sender_Sym  : constant String := "demo";
   From_Addr   : constant String := "demo@example-app.local";

   Tenant : constant Id.Tenant_Id :=
     Id.Tenant_Id (IP.From_Bytes ([1 .. 16 => 1]));

   function Bytes (N : Natural) return Stream_Element_Array is
     ([1 .. 16 => Stream_Element (N)]);

   ---------------------------------------------------------------------------
   --  A real system clock: Ada.Calendar mapped to a Unix-timeline Instant.
   ---------------------------------------------------------------------------
   type System_Clock is limited new Tm.Clock_Interface with null record;
   overriding function Now (Clock : System_Clock) return Tm.Instant;

   overriding function Now (Clock : System_Clock) return Tm.Instant is
      pragma Unreferenced (Clock);
      use type Ada.Calendar.Time;
      Epoch : constant Ada.Calendar.Time := Ada.Calendar.Time_Of (1970, 1, 1, 0.0);
      D     : constant Duration := Ada.Calendar.Clock - Epoch;
      Total : constant Long_Long_Float := Long_Long_Float (D);
      Secs  : constant Long_Long_Integer :=
        Long_Long_Integer (Long_Long_Float'Floor (Total));
      Frac  : constant Long_Long_Float := Total - Long_Long_Float (Secs);
      Nanos : constant Natural :=
        Natural'Min (999_999_999,
                     Natural (Long_Long_Float'Floor (Frac * 1.0E9)));
   begin
      return (Unix_Seconds => Secs, Nanoseconds => Nanos);
   end Now;

   ---------------------------------------------------------------------------
   --  A monotonic-counter id source (protected: request handlers run
   --  concurrently on the server).
   ---------------------------------------------------------------------------
   protected Counter is
      procedure Next (N : out Natural);
   private
      Value : Natural := 0;
   end Counter;

   protected body Counter is
      procedure Next (N : out Natural) is
      begin
         Value := Value + 1;
         N := Value;
      end Next;
   end Counter;

   type Counter_Ids is limited new Svc.Id_Source with null record;
   overriding function Fresh (Source : in out Counter_Ids) return IP.Opaque_Id;

   overriding function Fresh (Source : in out Counter_Ids) return IP.Opaque_Id is
      pragma Unreferenced (Source);
      N : Natural;
      A : Stream_Element_Array (1 .. 16) := [others => 7];
   begin
      Counter.Next (N);
      --  Spread the counter across the low bytes so successive ids differ even
      --  past 255 draws (ample for a demo).
      A (1) := Stream_Element (N mod 256);
      A (2) := Stream_Element ((N / 256) mod 256);
      A (3) := Stream_Element ((N / 65_536) mod 256);
      return IP.From_Bytes (A);
   end Fresh;

   ---------------------------------------------------------------------------
   --  Recipient resolver: the recipient key IS the target email address; build
   --  a profile with a single verified email destination carrying it.
   ---------------------------------------------------------------------------
   type Email_Resolver is limited new Rcp.Recipient_Resolver with null record;
   overriding procedure Resolve_One
     (Self : in out Email_Resolver; Context : Rcp.Resolution_Context;
      Namespace : Id.Recipient_Namespace; Key : Id.Recipient_Key;
      Status : out Rcp.Resolve_Status; Profile : out Rcp.Recipient_Profile);
   overriding procedure Resolve_Selector
     (Self : in out Email_Resolver; Context : Rcp.Resolution_Context;
      Namespace : Id.Recipient_Selector_Namespace;
      Key : Id.Recipient_Selector_Key; Cursor : Id.Recipient_Key;
      Sink : in out Rcp.Profile_Sink'Class; Status : out Rcp.Selector_Status;
      Next_Cursor : out Id.Recipient_Key);

   function Mask (Email : String) return String is
     (if Email'Length = 0 then "***"
      else Email (Email'First) & "***");

   overriding procedure Resolve_One
     (Self : in out Email_Resolver; Context : Rcp.Resolution_Context;
      Namespace : Id.Recipient_Namespace; Key : Id.Recipient_Key;
      Status : out Rcp.Resolve_Status; Profile : out Rcp.Recipient_Profile)
   is
      pragma Unreferenced (Self, Context);
      B     : Rcp.Builder;
      AO    : Rcp.Add_Outcome;
      D     : Dst.Destination_Snapshot;
      D_Out : Dst.Snapshot_Outcome;
      Email : constant String := IP.Key_Image (IP.Text_Key (Key));
   begin
      Dst.Make
        (Result => D, Outcome => D_Out,
         Id      => Id.Destination_Id (IP.From_Bytes (Bytes (9))),
         Tenant  => Tenant,
         Channel => Id.Channel_Id (IP.To_Symbol ("email")),
         Address => Email, Masked => Mask (Email),
         Provenance => Dst.Application_Verified,
         Verification => Dst.Verified, Validity => Dst.Valid,
         Version => 1, Snapshot_Time => Tm.Epoch);
      Rcp.Start
        (B, Recipient => Id.Recipient_Id (IP.From_Bytes (Bytes (2))),
         Class => Rcp.Identity_Principal, Tenant => Tenant,
         Namespace => Namespace, Key => Key);
      Rcp.Set_Active (B, True);
      Rcp.Add_Destination (B, D, AO);
      Rcp.Build (B, Profile);
      Status := Rcp.Resolved;
   end Resolve_One;

   overriding procedure Resolve_Selector
     (Self : in out Email_Resolver; Context : Rcp.Resolution_Context;
      Namespace : Id.Recipient_Selector_Namespace;
      Key : Id.Recipient_Selector_Key; Cursor : Id.Recipient_Key;
      Sink : in out Rcp.Profile_Sink'Class; Status : out Rcp.Selector_Status;
      Next_Cursor : out Id.Recipient_Key)
   is
      pragma Unreferenced (Self, Context, Namespace, Key, Cursor, Sink);
   begin
      Status := Rcp.Selector_Unavailable;
      Next_Cursor := Id.Empty_Recipient_Key;
   end Resolve_Selector;

   ---------------------------------------------------------------------------
   --  Sender directory: resolve the message's Sender symbol to a real address.
   ---------------------------------------------------------------------------
   type Static_Sender is limited new NE.Sender_Directory with null record;
   overriding procedure Resolve_Sender
     (Dir : in out Static_Sender; Sender : IP.Symbol;
      Config : Pv.Provider_Configuration; Context : Pv.Send_Context;
      Address : out NE.Address_Text.Bounded_Text; Found : out Boolean);

   overriding procedure Resolve_Sender
     (Dir : in out Static_Sender; Sender : IP.Symbol;
      Config : Pv.Provider_Configuration; Context : Pv.Send_Context;
      Address : out NE.Address_Text.Bounded_Text; Found : out Boolean)
   is
      pragma Unreferenced (Dir, Sender, Config, Context);
   begin
      Address := NE.Address_Text.To_Bounded (From_Addr);
      Found   := True;
   end Resolve_Sender;

   ---------------------------------------------------------------------------
   --  Last provider outcome (protected: the engine's delivery step -- running
   --  in the request task -- writes it; the page reads it).
   ---------------------------------------------------------------------------
   protected Last_Provider is
      procedure Reset;
      procedure Note (Class : PR.Provider_Result_Class;
                      Certainty : PR.Outcome_Certainty);
      procedure Snapshot (Called : out Boolean;
                          Class : out PR.Provider_Result_Class;
                          Certainty : out PR.Outcome_Certainty);
   private
      Has   : Boolean := False;
      C     : PR.Provider_Result_Class := PR.Success;
      Cert  : PR.Outcome_Certainty := PR.Unknown;
   end Last_Provider;

   protected body Last_Provider is
      procedure Reset is
      begin
         Has := False;
      end Reset;
      procedure Note (Class : PR.Provider_Result_Class;
                      Certainty : PR.Outcome_Certainty) is
      begin
         Has := True; C := Class; Cert := Certainty;
      end Note;
      procedure Snapshot (Called : out Boolean;
                          Class : out PR.Provider_Result_Class;
                          Certainty : out PR.Outcome_Certainty) is
      begin
         Called := Has; Class := C; Certainty := Cert;
      end Snapshot;
   end Last_Provider;

   ---------------------------------------------------------------------------
   --  Recording provider: delegates to the real email provider and records the
   --  provider result class/certainty so the page can display the confidence.
   ---------------------------------------------------------------------------
   type Recording_Provider (Inner : access Pv.Provider'Class) is
     limited new Pv.Provider with null record;
   overriding procedure Send
     (Self : in out Recording_Provider; Context : Pv.Send_Context;
      Config : Pv.Provider_Configuration; Artifact : Rd.Rendered_Artifact;
      Result : out Pv.Provider_Result);

   overriding procedure Send
     (Self : in out Recording_Provider; Context : Pv.Send_Context;
      Config : Pv.Provider_Configuration; Artifact : Rd.Rendered_Artifact;
      Result : out Pv.Provider_Result)
   is
   begin
      Self.Inner.Send (Context, Config, Artifact, Result);
      Last_Provider.Note (Pv.Class (Result), Pv.Certainty (Result));
   end Send;

   ---------------------------------------------------------------------------
   --  Long-lived composed state (built in Initialize).
   ---------------------------------------------------------------------------
   Started : Boolean := False;

   --  smtplib transport backends (real sockets to the catcher). Body-level so
   --  they outlive the configuration that references them.
   Net_Resolver  : aliased DN.Dns_Resolver :=
     DN.Make_Resolver (Port => Smtplib.Port_Number (App.Smtp_Catcher.Listen_Port));
   Net_Connector : aliased DN.Socket_Connector := DN.Make_Connector;
   Net_RNG       : aliased DR.Os_Random_Source := DR.Make;

   Sender_Dir : aliased Static_Sender;

   type Email_Provider_Access    is access all NE.Email_Provider;
   type Recording_Provider_Access is access all Recording_Provider;

   Store_Ptr    : MS.Memory_Store_Access;
   Clock_Ptr    : access System_Clock;
   Ids_Ptr      : access Counter_Ids;
   Resolver_Ptr : access Email_Resolver;
   Renderer_Ptr : access NT.Renderer;
   Registry_Ptr : access K.Registry;
   Config_Ptr   : access constant Cfg.Client_Configuration;
   Email_Ptr    : Email_Provider_Access;
   Wrapper_Ptr  : Recording_Provider_Access;

   Provider_Cfg : Pv.Provider_Configuration;
   Engine       : Svc.Engine;

   ---------------------------------------------------------------------------
   --  Composition helpers.
   ---------------------------------------------------------------------------
   function Demo_Schema return Sc.Payload_Schema is
      B : Sc.Builder := Sc.Start (1);   --  schema version (matches payload v1)
      O : Sc.Add_Field_Outcome;
   begin
      Sc.Add_Field (B, (Id => Pl.To_Field_Id ("subject"), Required => True,
                        Kind => Val.Text_Value, others => <>), O);
      Sc.Add_Field (B, (Id => Pl.To_Field_Id ("message"), Required => True,
                        Kind => Val.Text_Value, others => <>), O);
      return Sc.Finish (B);
   end Demo_Schema;

   function Demo_Payload (Subject, Message : String) return Pl.Payload is
      B  : Pl.Builder := Pl.Start (1);   --  payload version 1
      O  : Pl.Add_Outcome;
      V  : Val.Value;
      TO : Val.Value_Outcome;
   begin
      Val.Of_Text (Subject, V, TO);
      Pl.Add (B, Pl.To_Field_Id ("subject"), V,
              Cls.Public, Cls.No_Redaction, Cls.Operational, O);
      Val.Of_Text (Message, V, TO);
      Pl.Add (B, Pl.To_Field_Id ("message"), V,
              Cls.Public, Cls.No_Redaction, Cls.Operational, O);
      return Pl.Finish (B);
   end Demo_Payload;

   --  Build the plaintext, no-auth, localhost smtplib configuration targeting
   --  the catcher, over the real network backend.
   procedure Build_Config (Ok : out Boolean) is
      B : Cfg.Configuration_Builder :=
        Cfg.Unauthenticated_Relay
          (Host     => "127.0.0.1",
           Ehlo     => "example-app.local",
           Port     => Smtplib.Port_Number (App.Smtp_Catcher.Listen_Port),
           Security => Net.Plaintext,
           Ack      => Cfg.Acknowledge_Unauthenticated_Relay);
      RT : constant Cfg.Client_Runtime :=
        Cfg.Make_Runtime
          (Resolver     => Net_Resolver'Access,
           Connector    => Net_Connector'Access,
           Random       => Net_RNG'Access,
           Capabilities => DN.Capabilities);
      CR : Cfg.Configuration_Result;
   begin
      Cfg.Set_Runtime (B, RT);
      --  smtplib's own auto-retry is disabled: the notifications engine owns
      --  retry sequencing, so each Send maps exactly one attempt.
      Cfg.Set_Retry (B, Cfg.No_Retry);
      CR := Cfg.Finalize (B);
      if not Cfg.Is_Success (CR) then
         Ok := False;
         return;
      end if;
      Config_Ptr := new Cfg.Client_Configuration'(Cfg.Value (CR));
      Ok := True;
   end Build_Config;

   ---------------------------------------------------------------------------
   --  Initialize.
   ---------------------------------------------------------------------------
   procedure Initialize (Status : out Init_Status) is
      Reg_Out    : K.Register_Outcome;
      Fin_Out    : K.Finalize_Outcome;
      Rnd_Out    : NT.Register_Outcome;
      Config_Ok  : Boolean;
   begin
      if Started then
         Status := Ready;
         return;
      end if;

      --  The store is large: heap-allocate it (a stack Memory_Store overflows).
      Store_Ptr    := new MS.Memory_Store;
      Clock_Ptr    := new System_Clock;
      Ids_Ptr      := new Counter_Ids;
      Resolver_Ptr := new Email_Resolver;
      Renderer_Ptr := new NT.Renderer;
      Registry_Ptr := new K.Registry;

      --  Register the email.demo kind on the email channel.
      declare
         Chans : constant K.Channel_Set :=
           K.With_Channel (K.Empty_Channels, Id.Channel_Id (IP.To_Symbol ("email")));
         Def : constant K.Kind_Definition :=
           K.Make (Id => Id.To_Symbol (Kind_Symbol),
                   Definition_Version => 1, Current_Payload_Version => 1,
                   Min_Supported_Version => 1, Current_Schema => Demo_Schema,
                   Permitted_Channels => Chans);
         use type K.Register_Outcome;
         use type K.Finalize_Outcome;
      begin
         K.Register (Registry_Ptr.all, Def, Reg_Out);
         if Reg_Out /= K.Registered then
            Status := Kind_Register_Error;
            return;
         end if;
         K.Finalize (Registry_Ptr.all, Fin_Out);
         if Fin_Out /= K.Finalized then
            Status := Kind_Finalize_Error;
            return;
         end if;
      end;

      --  Register the email template for the kind. The payload fields subject /
      --  message bind to the {{{subject}}} / {{{message}}} template tags.
      NT.Register_Email
        (Self      => Renderer_Ptr.all,
         Kind      => Id.To_Symbol (Kind_Symbol),
         Sender    => IP.To_Symbol (Sender_Sym),
         Subject   => "{{{subject}}}",
         Text_Body => "{{{message}}}",
         HTML_Body => "<p>{{message}}</p>",
         Trust     => Msg.Escaped_HTML_Template,
         Outcome   => Rnd_Out);
      if Rnd_Out /= NT.Registered then
         Status := Renderer_Error;
         return;
      end if;

      --  The smtplib configuration and the email provider over it.
      Build_Config (Config_Ok);
      if not Config_Ok then
         Status := Config_Error;
         return;
      end if;
      Email_Ptr := new NE.Email_Provider
        (Client   => Config_Ptr,
         Senders  => Sender_Dir'Access,
         Attacher => null);   --  attachments disabled in this demo
      Wrapper_Ptr := new Recording_Provider
        (Inner => Pv.Provider_Access (Email_Ptr));

      --  The provider configuration (endpoint/auth live in the smtplib config;
      --  this just names the provider).
      declare
         CB : Pv.Config_Builder;
      begin
         Pv.Start (CB, Id.Provider_Id (IP.To_Symbol ("provider.smtp")), 1);
         Pv.Finish (CB, Provider_Cfg);
      end;

      Engine :=
        (Store           => Rep.Store_Access (Store_Ptr),
         Clock           => Tm.Clock_Access (Clock_Ptr),
         Ids             => Svc.Id_Source_Access (Ids_Ptr),
         Resolver        => Rcp.Recipient_Resolver_Access (Resolver_Ptr),
         Renderer        => Rd.Renderer_Access (Renderer_Ptr),
         Registry        => Svc.Registry_Access (Registry_Ptr),
         Provider        => Pv.Provider_Access (Wrapper_Ptr),
         Provider_Config => Provider_Cfg,
         Retry_Policy    => Rt.Make (Id.To_Symbol ("retry.default"), Jitter => 0),
         others          => <>);

      Started := True;
      Status  := Ready;
   exception
      when others =>
         Status := Store_Error;
   end Initialize;

   ---------------------------------------------------------------------------
   --  Last-send store (for the demo page after the POST redirects to GET).
   ---------------------------------------------------------------------------
   protected Last_Store is
      procedure Put (R : Send_Result);
      function  Get return Send_Result;
   private
      Value : Send_Result;
   end Last_Store;

   protected body Last_Store is
      procedure Put (R : Send_Result) is
      begin
         Value := R;
      end Put;
      function Get return Send_Result is (Value);
   end Last_Store;

   function Last_Send return Send_Result is (Last_Store.Get);

   ---------------------------------------------------------------------------
   --  Send.
   ---------------------------------------------------------------------------
   procedure Do_Send
     (To_Email : String;
      Subject  : String;
      Message  : String;
      Result   : out Send_Result)
   is
      B       : In_T.Builder;
      Intent  : In_T.Intent;
      A_Out   : In_T.Add_Recipient_Outcome;
      B_Out   : In_T.Build_Outcome;
      C_Res   : Svc.Create_Result;
      N_Id    : Id.Notification_Id;
      O       : Rep.Repository_Outcome;
      Steps   : Natural := 0;
      Seq     : Natural;
      Before  : constant Natural := App.Smtp_Catcher.Count;
      P_Called : Boolean;
      P_Class  : PR.Provider_Result_Class;
      P_Cert   : PR.Outcome_Certainty;
   begin
      Result := (others => <>);
      if not Started then
         Result.Phase := Not_Started;
         return;
      end if;

      Last_Provider.Reset;
      Counter.Next (Seq);

      In_T.Start
        (B, Kind => Id.To_Symbol (Kind_Symbol), Tenant => Tenant,
         Payload => Demo_Payload (Subject, Message),
         Idempotency => Id.To_Key ("email-demo-" & Natural'Image (Seq)));
      In_T.Add_Recipient
        (B, Id.To_Symbol ("identity_principal"), Id.To_Key (To_Email), A_Out);
      In_T.Build (B, Intent, B_Out);
      if B_Out /= In_T.Ok then
         Result.Phase := Create_Rejected;
         Result.Create_Image := To_Unbounded_String (In_T.Build_Outcome'Image (B_Out));
         return;
      end if;

      Svc.Create (Engine, Intent, C_Res, N_Id, O);
      Result.Create_Image := To_Unbounded_String (Svc.Create_Result'Image (C_Res));
      if C_Res /= Svc.Created then
         Result.Phase := Create_Rejected;
         return;
      end if;
      Result.Created := True;
      Result.Phase   := Built;

      Svc.Drive (Engine, Steps_Run => Steps);
      Result.Steps_Run := Steps;

      Last_Provider.Snapshot (P_Called, P_Class, P_Cert);
      Result.Provider_Called := P_Called;
      if P_Called then
         Result.Provider_Class :=
           To_Unbounded_String (PR.Provider_Result_Class'Image (P_Class));
         Result.Provider_Certainty :=
           To_Unbounded_String (PR.Outcome_Certainty'Image (P_Cert));
      end if;
      Result.Reached_Catcher := App.Smtp_Catcher.Count > Before;
      Result.Phase := Delivered_Attempt;
   exception
      when others =>
         Result.Phase := Send_Error;
   end Do_Send;

   procedure Send
     (To_Email : String;
      Subject  : String;
      Message  : String;
      Result   : out Send_Result) is
   begin
      Do_Send (To_Email, Subject, Message, Result);
      Last_Store.Put (Result);
   end Send;

end App.Notifications;
