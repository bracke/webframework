with Web.Binding;              use Web.Binding;
with Web.Binding.Paths;        use Web.Binding.Paths;
with Web.Binding.Policies;     use Web.Binding.Policies;
with Web.Binding.Query;
with Web.Binding.Record_Binders;
with Web.Binding.Decoders.Integer_Decoders;
with Web.Binding.Decoders.Boolean_Decoders;

package body App.Query_Binding is

   procedure Set_Page (Rec : in out Projects_Query; Value : Page_Number) is
   begin
      Rec.Page := Value;
   end Set_Page;

   procedure Set_Alire (Rec : in out Projects_Query; Value : Boolean) is
   begin
      Rec.Alire_Only := Value;
   end Set_Alire;

   package RB is new Web.Binding.Record_Binders (Projects_Query);
   package Page_Dec is new Web.Binding.Decoders.Integer_Decoders (Page_Number);
   package Bool_Dec renames Web.Binding.Decoders.Boolean_Decoders;

   function Page_Decode
     (Text : String; P : Field_Path; S : Source_Kind)
      return Page_Dec.Results.Result is (Page_Dec.Decode (Text, P, S));

   function Bool_Decode
     (Text : String; P : Field_Path; S : Source_Kind)
      return Bool_Dec.Results.Result is (Bool_Dec.Decode (Text, P, S));

   procedure Bind_Page is new RB.Bind_Scalar
     (Page_Number, Page_Dec.Results, Page_Decode, Set_Page);
   procedure Bind_Alire is new RB.Bind_Scalar
     (Boolean, Bool_Dec.Results, Bool_Decode, Set_Alire);

   Page_Path : constant Field_Path :=
     Append_Field (Rooted (Query_Parameter), "page");
   Alire_Path : constant Field_Path :=
     Append_Field (Rooted (Query_Parameter), "alire_only");

   function Bind (Request : Web.Request.Request_Type) return Projects_Query is
      Src : constant Web.Binding.Query.Query_Source :=
        Web.Binding.Query.Parse (Web.Request.Query_String (Request));
      B      : RB.Builder := RB.Start ((Page => 1, Alire_Only => False));
      Result : RB.Results.Result;
   begin
      Bind_Page
        (B, Web.Binding.Query.Lookup (Src, "page"), Page_Path, Query_Parameter,
         Optional_With_Default);
      Bind_Alire
        (B, Web.Binding.Query.Lookup (Src, "alire_only"), Alire_Path,
         Query_Parameter, Optional_With_Default);
      Result := RB.Finish (B);
      if RB.Results.Succeeded (Result) then
         return RB.Results.Value_Of (Result);
      else
         return (Page => 1, Alire_Only => False);
      end if;
   end Bind;

end App.Query_Binding;
