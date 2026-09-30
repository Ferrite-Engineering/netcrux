-- 4-bit incrementer used as the VHDL submodule in the mixed-language
-- fixture. The Verilog top instantiates this via a black-box prototype.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity sub is
  port (
    a : in  std_logic_vector(3 downto 0);
    y : out std_logic_vector(3 downto 0)
  );
end entity sub;

architecture rtl of sub is
begin
  y <= std_logic_vector(unsigned(a) + 1);
end architecture rtl;
