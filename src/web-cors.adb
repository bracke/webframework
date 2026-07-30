with Ada.Strings.Fixed;

package body Web.CORS is

   function Make
     (Origins     : String;
      Methods     : String := "GET, POST, PUT, PATCH, DELETE, OPTIONS";
      Headers     : String := "Content-Type";
      Expose      : String := "";
      Credentials : Boolean := False;
      Max_Age     : Natural := 0) return Policy
   is
      P : Policy;
   begin
      P.Origins     := To_Unbounded_String (Origins);
      P.Any_Origin  := Origins = "*";
      P.Methods     := To_Unbounded_String (Methods);
      P.Headers     := To_Unbounded_String (Headers);
      P.Expose      := To_Unbounded_String (Expose);
      P.Credentials := Credentials;
      P.Max_Age     := Max_Age;
      return P;
   end Make;

   --  Whether Origin is on the policy's comma-separated allowlist.
   function Origin_Allowed (P : Policy; Origin : String) return Boolean is
      List   : constant String := To_String (P.Origins);
      Cursor : Natural := List'First;
   begin
      if P.Any_Origin then
         return True;
      end if;
      while Cursor <= List'Last loop
         declare
            Comma : constant Natural :=
              Ada.Strings.Fixed.Index (List (Cursor .. List'Last), ",");
            Stop  : constant Natural :=
              (if Comma = 0 then List'Last else Comma - 1);
            Item  : constant String :=
              Ada.Strings.Fixed.Trim
                (List (Cursor .. Stop), Ada.Strings.Both);
         begin
            if Item = Origin then
               return True;
            end if;
            exit when Comma = 0;
            Cursor := Comma + 1;
         end;
      end loop;
      return False;
   end Origin_Allowed;

   function Allows_Origin (P : Policy; Origin : String) return Boolean is
     (Origin'Length > 0 and then Origin_Allowed (P, Origin));

   procedure Apply
     (P        : Policy;
      Request  : Web.Request.Request_Type;
      Response : in out Web.Response.Response_Type)
   is
      Origin : constant String := Web.Request.Header (Request, "origin");
   begin
      if Origin'Length = 0 or else not Origin_Allowed (P, Origin) then
         return;   --  not a CORS request, or the origin is not allowed
      end if;

      if P.Any_Origin and then not P.Credentials then
         Web.Response.Set_Header (Response, "Access-Control-Allow-Origin", "*");
      else
         --  A specific origin (or credentials) must be echoed, and the response
         --  then varies by Origin.
         Web.Response.Set_Header (Response, "Access-Control-Allow-Origin", Origin);
         Web.Response.Ensure_Vary (Response, "Origin");
      end if;

      if P.Credentials then
         Web.Response.Set_Header
           (Response, "Access-Control-Allow-Credentials", "true");
      end if;

      if Length (P.Expose) > 0 then
         Web.Response.Set_Header
           (Response, "Access-Control-Expose-Headers", To_String (P.Expose));
      end if;

      --  Preflight: an OPTIONS carrying Access-Control-Request-Method.
      if Web.Request.Method (Request) = "OPTIONS"
        and then Web.Request.Header
                   (Request, "access-control-request-method")'Length > 0
      then
         Web.Response.Set_Header
           (Response, "Access-Control-Allow-Methods", To_String (P.Methods));
         if Length (P.Headers) > 0 then
            Web.Response.Set_Header
              (Response, "Access-Control-Allow-Headers", To_String (P.Headers));
         end if;
         if P.Max_Age > 0 then
            Web.Response.Set_Header
              (Response, "Access-Control-Max-Age",
               Ada.Strings.Fixed.Trim
                 (Natural'Image (P.Max_Age), Ada.Strings.Both));
         end if;
      end if;
   end Apply;

end Web.CORS;
