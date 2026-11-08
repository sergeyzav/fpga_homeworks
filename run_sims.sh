#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "========================================"
echo "Starting FPGA Homework Simulations via Icarus Verilog"
echo "========================================"

FAILED_TESTS=()
PASSED_TESTS=()
SKIPPED_TESTS=()

# Projects that cannot run in Icarus (they need Vivado-generated IP).
SKIP_DIRS=(
    "./homework_5/hw/mainproject"   # MicroBlaze block design
)

SIM_DIRS=$(find . -type d -name "sim" | sort)

if [ -z "$SIM_DIRS" ]; then
    echo -e "${RED}No 'sim' directories found in the workspace!${NC}"
    exit 1
fi

for SIM_DIR in $SIM_DIRS; do
    PARENT_DIR=$(dirname "$SIM_DIR")
    PROJECT_NAME=$(basename "$PARENT_DIR")

    if [[ " ${SKIP_DIRS[*]} " == *" $PARENT_DIR "* ]]; then
        echo ""
        echo -e "${YELLOW}Skipping $PROJECT_NAME ($PARENT_DIR): needs Vivado${NC}"
        SKIPPED_TESTS+=("$PROJECT_NAME")
        continue
    fi

    echo ""
    echo "========================================================================"
    echo "Processing project: $PROJECT_NAME ($PARENT_DIR)"
    echo "========================================================================"
    
    # Design sources: src/ (hand-written) and ip/ (e.g. HLS-generated Verilog).
    SRC_FILES=""
    for D in src ip; do
        if [ -d "$PARENT_DIR/$D" ]; then
            SRC_FILES="$SRC_FILES $(find "$PARENT_DIR/$D" -type f \( -name "*.sv" -o -name "*.v" \) 2>/dev/null)"
        fi
    done
    SRC_FILES=$(echo $SRC_FILES)
    SIM_FILES=$(find "$PARENT_DIR/sim" -type f \( -name "*.sv" -o -name "*.v" \) 2>/dev/null)
    
    if [ -z "$SIM_FILES" ]; then
        echo -e "${YELLOW}Warning: No simulation files found in $PARENT_DIR/sim, skipping...${NC}"
        continue
    fi
    
    echo "Source files:"
    if [ -n "$SRC_FILES" ]; then
        echo "$SRC_FILES"
    else
        echo "None"
    fi
    echo "Simulation files:"
    echo "$SIM_FILES"
    
    VVP_OUT="$PARENT_DIR/sim.vvp"
    LOG_FILE="$PARENT_DIR/sim.log"
    
    echo "Compiling with iverilog..."
    iverilog -g2012 -o "$VVP_OUT" $SRC_FILES $SIM_FILES
    COMPILE_STATUS=$?
    
    if [ $COMPILE_STATUS -ne 0 ]; then
        echo -e "${RED}Compilation FAILED for $PROJECT_NAME${NC}"
        FAILED_TESTS+=("$PROJECT_NAME (Compilation)")
        continue
    fi
    
    echo "Running simulation with vvp..."
    vvp "$VVP_OUT" > "$LOG_FILE" 2>&1
    VVP_STATUS=$?
    
    cat "$LOG_FILE"
    
    rm -f "$VVP_OUT"
    
    if [ $VVP_STATUS -ne 0 ]; then
        echo -e "${RED}Simulation crashed or returned non-zero exit code $VVP_STATUS for $PROJECT_NAME${NC}"
        FAILED_TESTS+=("$PROJECT_NAME (Crash/Exit)")
    elif grep -iqE "fail|error" "$LOG_FILE"; then
        echo -e "${RED}Simulation failed (detected 'fail' or 'error' in output) for $PROJECT_NAME${NC}"
        FAILED_TESTS+=("$PROJECT_NAME (Assertion)")
    else
        echo -e "${GREEN}Simulation PASSED for $PROJECT_NAME!${NC}"
        PASSED_TESTS+=("$PROJECT_NAME")
    fi
    
    rm -f "$LOG_FILE"
done

echo ""
echo "========================================"
echo "Simulation Summary"
echo "========================================"
echo -e "${GREEN}Passed (${#PASSED_TESTS[@]}): ${PASSED_TESTS[*]}${NC}"
if [ ${#SKIPPED_TESTS[@]} -ne 0 ]; then
    echo -e "${YELLOW}Skipped (${#SKIPPED_TESTS[@]}): ${SKIPPED_TESTS[*]}${NC}"
fi

if [ ${#FAILED_TESTS[@]} -ne 0 ]; then
    echo -e "${RED}Failed (${#FAILED_TESTS[@]}): ${FAILED_TESTS[*]}${NC}"
    exit 1
else
    echo -e "${GREEN}All simulations completed successfully!${NC}"
    exit 0
fi
