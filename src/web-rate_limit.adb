with Ada.Strings.Hash;
with Ada.Containers; use type Ada.Containers.Hash_Type;

package body Web.Rate_Limit is

   Capacity : constant := 4096;    --  distinct clients tracked at once
   Max_Key  : constant := 128;     --  longest client key kept (IP text)
   Probes   : constant := 8;       --  bounded linear probe / eviction window

   type Slot is record
      In_Use  : Boolean := False;
      Key     : String (1 .. Max_Key) := [others => ' '];
      Key_Len : Natural := 0;
      Window  : Timestamp := 0;     --  start of the current window
      Count   : Natural := 0;       --  requests seen in this window
   end record;
   type Slot_Array is array (0 .. Capacity - 1) of Slot;

   --  All state behind one lock: correctness first. A request holds it only for
   --  the bounded probe below.
   protected Store is
      procedure Configure (Max_Requests : Natural; Window_Seconds : Positive);
      procedure Check
        (Client      : String;
         Now         : Timestamp;
         Allowed     : out Boolean;
         Retry_After : out Natural);
   private
      Limit : Natural := 0;         --  0 disables limiting
      Win   : Positive := 60;
      Slots : Slot_Array;
   end Store;

   protected body Store is

      procedure Configure (Max_Requests : Natural; Window_Seconds : Positive) is
      begin
         Limit := Max_Requests;
         Win   := Window_Seconds;
         for S of Slots loop
            S.In_Use  := False;
            S.Key_Len := 0;
            S.Window  := 0;
            S.Count   := 0;
         end loop;
      end Configure;

      procedure Check
        (Client      : String;
         Now         : Timestamp;
         Allowed     : out Boolean;
         Retry_After : out Natural)
      is
         Home       : constant Natural :=
           Natural (Ada.Strings.Hash (Client) mod Capacity);
         Match      : Integer := -1;   --  slot already tracking this client
         Reusable   : Integer := -1;   --  first free or expired slot
         Oldest     : Natural := Home; --  oldest window among probed, for eviction
      begin
         Allowed := True;
         Retry_After := 0;
         if Limit = 0 then
            return;   --  disabled
         end if;

         for P in 0 .. Probes - 1 loop
            declare
               Idx : constant Natural := (Home + P) mod Capacity;
               S   : Slot renames Slots (Idx);
            begin
               if S.In_Use
                 and then S.Key_Len = Client'Length
                 and then S.Key (1 .. S.Key_Len) = Client
               then
                  Match := Idx;
                  exit;
               elsif not S.In_Use or else Now - S.Window >= Timestamp (Win) then
                  if Reusable < 0 then
                     Reusable := Idx;
                  end if;
               end if;
               if S.Window < Slots (Oldest).Window then
                  Oldest := Idx;
               end if;
            end;
         end loop;

         if Match >= 0 then
            declare
               S : Slot renames Slots (Match);
            begin
               if Now - S.Window >= Timestamp (Win) then
                  S.Window := Now;      --  a fresh window
                  S.Count  := 1;
               else
                  S.Count := S.Count + 1;
                  if S.Count > Limit then
                     Allowed := False;
                     Retry_After :=
                       Natural (S.Window + Timestamp (Win) - Now);
                  end if;
               end if;
            end;
         else
            --  New client: take a free/expired slot, else evict the oldest.
            declare
               Target : constant Natural :=
                 (if Reusable >= 0 then Reusable else Oldest);
               Len    : constant Natural := Natural'Min (Client'Length, Max_Key);
               S      : Slot renames Slots (Target);
            begin
               S.In_Use  := True;
               S.Key_Len := Len;
               S.Key (1 .. Len) := Client (Client'First .. Client'First + Len - 1);
               S.Window  := Now;
               S.Count   := 1;
            end;
         end if;
      end Check;

   end Store;

   procedure Configure (Max_Requests : Natural; Window_Seconds : Positive) is
   begin
      Store.Configure (Max_Requests, Window_Seconds);
   end Configure;

   procedure Check
     (Client      : String;
      Now         : Timestamp;
      Allowed     : out Boolean;
      Retry_After : out Natural) is
   begin
      Store.Check (Client, Now, Allowed, Retry_After);
   end Check;

end Web.Rate_Limit;
