with AUnit.Test_Cases;

package Textrender.BasicTests is

   type Textrender_Basic_Case is new AUnit.Test_Cases.Test_Case with null record;

   overriding
   function Name
     (T : Textrender_Basic_Case) return AUnit.Message_String;

   overriding
   procedure Register_Tests
     (T : in out Textrender_Basic_Case);

end Textrender.BasicTests;