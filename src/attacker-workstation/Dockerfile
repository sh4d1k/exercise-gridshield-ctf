FROM gridshield/common:public
RUN useradd -m -s /bin/bash devuser && echo 'devuser:Infradev#99' | chpasswd && mkdir -p /home/devuser/.ssh
COPY setup.sh /usr/local/bin/m4-setup
RUN chmod +x /usr/local/bin/m4-setup
CMD ["/usr/local/bin/m4-setup"]
