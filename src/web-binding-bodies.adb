package body Web.Binding.Bodies is

   function New_Body return Body_Claim is
   begin
      return C : Body_Claim do
         C.Current := Available;
      end return;
   end New_Body;

   function State (Item : Body_Claim) return Body_State is
   begin
      return Item.Current;
   end State;

   procedure Claim (Item : in out Body_Claim; Ok : out Boolean) is
   begin
      if Item.Current = Available then
         Item.Current := Decoding;
         Ok := True;
      else
         Ok := False;
      end if;
   end Claim;

   procedure Release (Item : in out Body_Claim; Success : Boolean) is
   begin
      Item.Current := (if Success then Consumed else Failed);
   end Release;

end Web.Binding.Bodies;
