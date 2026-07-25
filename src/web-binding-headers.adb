package body Web.Binding.Headers is

   function Has (Request : Web.Request.Request_Type; Name : String)
      return Boolean is
   begin
      return Web.Request.Has_Header (Request, Name);
   end Has;

   function Lookup
     (Request : Web.Request.Request_Type; Name : String)
      return Web.Binding.Sources.Occurrences
   is
      Result : Web.Binding.Sources.Occurrences := Web.Binding.Sources.Empty;
   begin
      if Web.Request.Has_Header (Request, Name) then
         Web.Binding.Sources.Add
           (Result, Web.Request.Header (Request, Name));
      end if;
      return Result;
   end Lookup;

end Web.Binding.Headers;
