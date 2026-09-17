// alu.sv
// ALU з РЕЄСТРОВИМИ входами і РЕЄСТРОВИМ виходом (2-тактова затримка).
// Плюс oe (output enable) — не для функціональності ALU як такої,
// а щоб мати законний, реальний спосіб продемонструвати стан Z
// (tri-state) на цьому ж модулі.

module alu (
    input  logic        clk,
    input  logic        rst,     // асинхронний reset, активний високим рівнем
    input  logic [3:0]  a,
    input  logic [3:0]  b,
    input  logic [1:0]  op,      // 00=+, 01=-, 10=AND, 11=OR
    input  logic        oe,      // output enable: 0 -> вихід у стані Z
    output logic [3:0]  result
);

    // ---- Стадія 1: реєстрові входи ----
    logic [3:0] a_reg, b_reg;
    logic [1:0] op_reg;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            a_reg  <= 4'd0;
            b_reg  <= 4'd0;
            op_reg <= 2'd0;
        end else begin
            a_reg  <= a;
            b_reg  <= b;
            op_reg <= op;
        end
    end

    // ---- Комбінаційна логіка ALU (працює вже з реєстрових входів) ----
    logic [3:0] alu_result;

    always_comb begin
        alu_result = 4'd0;               // default — без цього ризик latch
        case (op_reg)
            2'b00:   alu_result = a_reg + b_reg;
            2'b01:   alu_result = a_reg - b_reg;
            2'b10:   alu_result = a_reg & b_reg;
            2'b11:   alu_result = a_reg | b_reg;
            default: alu_result = 4'd0;
        endcase
    end

    // ---- Стадія 2: реєстровий вихід ----
    logic [3:0] result_reg;

    always_ff @(posedge clk or posedge rst) begin
        if (rst)
            result_reg <= 4'd0;
        else
            result_reg <= alu_result;
    end

    // ---- Tri-state вихід: oe=0 -> Z (демонстрація стану Z) ----
    assign result = oe ? result_reg : 4'bzzzz;

endmodule