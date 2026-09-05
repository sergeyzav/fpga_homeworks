`timescale 1ns / 1ps

module tb_counter;

    reg clk;
    reg rst;
    reg load;
    reg [3:0] data_in;
    reg en;
    reg up_down;
    wire [3:0] count;

    counter counter (
        .clk(clk),
        .rst(rst),
        .load(load),
        .data_in(data_in),
        .en(en),
        .up_down(up_down),
        .count(count)
    );

    always #5 clk = ~clk;

    task automatic check_count(input [3:0] expected, input string name);
        if (count !== expected)
            $error("Fail %s expected=%d got=%d", name, expected, count);
        else
            $display("PASS %s", name);
    endtask

    

    initial begin
        clk = 0;
        
        rst = 1;
        #1;
        rst = 0;

        load = 1;
        data_in = 4'd10;
        @(posedge clk); #1;
        load = 0;
        check_count(10, "load=1");
       
        en = 1;
        up_down = 1;
        repeat (3) begin
            @(posedge clk);
            #1;
        end
        check_count(13, "en=1 up_down=1");
        
        repeat (3) begin
            @(posedge clk);
            #1;
        end
        check_count(0, "en=1 up_down=1");

        en = 0;
        repeat (2) begin
            @(posedge clk);
            #1;
        end
        check_count(0, "en=0");
        
        en = 1;
        up_down = 0;
        @(posedge clk);#1;
        check_count(15, "en=1 up_down=0");
        
        en = 1;
        load = 1;
        data_in = 4'd5;
        @(posedge clk);#1;

        check_count(5, "load=1 over en=1");

        en = 1;
        load = 0;
        up_down = 0;
        @(posedge clk);#1;

        check_count(4, "en=1 up_down=0 5->4");

        #5;
        $finish; 
    end

endmodule