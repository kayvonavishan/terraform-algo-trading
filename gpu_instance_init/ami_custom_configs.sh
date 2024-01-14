#!/bin/bash
source activate pytorch
conda config --set channel_priority flexible
conda install -c conda-forge ta-lib plotly alpha_vantage ta pandasql itables jupyter pandas-ta
sudo apt install -q -y nvme-cli