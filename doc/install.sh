if [[ $OSTYPE == 'darwin'* ]]; then
    brew install basictex
    brew install pandoc
else
    sudo apt-get install pandoc texlive-latex-base texlive-fonts-recommended texlive-extra-utils texlive-latex-extra
fi