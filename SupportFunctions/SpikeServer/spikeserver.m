function [] = spikeserver(port, eventsonly, continuous)
% [] = spikeserver(port, eventsonly)
% SPIKESERVER sends plexon spikes over IP to another computer. Open a UDP 
% socket connect to plexon server (locally), then send spike times to 
% server client (on some other machine)
% Written by jly (heavily adapted from code by p. mineault)
% notes: code from xcorr.net uses PL_GETAD() which seems to be depreciated
% in 64-bit mex file provided by plexon
% INPUTS:
%   port - udp port (default is 3333)
%   eventsonly - 0 or 1 (all spikes or just events) 
%   continuous - 0 or 1 (sent spikes as they occur or on client request)
% (c) jly 09.16.2013 - (adapted from spikeserver.m by p. mineault)
% (c) jk  24.03.2015 - updated to receive settings from remote client

if nargin <3
    continuous=false;
    if nargin<2
        eventsonly = 0; 
        if nargin < 1
            port = 3333;
        end
    end
end

% addpath('tcp_udp_ip');
port_pause=0.010;
splice_pause=0.010;
%totalSpikesSent=0; for debugging, compare with totalSpikesReceived in
%spikeclient.m
maxpacketsize = 2e3;
timeout = 2;

    pnet('closeall');

    plx = PlxConnection();
    packetnum=1;
    if plx == 0
        error('Could not connect to Plexon server');
    else
        %Listen for an incoming connection on port #
        sock=pnet('udpsocket',port);
        
        if sock == -1
            error('Port %d is blocked',port);
        end

        %Only wait for 100 ms before giving up
        pnet(sock,'setreadtimeout',.002);
        pnet(sock,'setwritetimeout',1);

        disp('Waiting for client requests');
        
        clientisconnected = 0;
        connecttime = clock + 1;
        
        while 1
            
            msglen = pnet(sock,'readpacket');
            %Received a message
            if msglen > 0
                %Read instruction
                instruction = pnet(sock,'readline');
                fprintf('Received message from client... %s\n',instruction);
                switch instruction
                    case 'MARCO'
                        if clientisconnected
                            disp('Client was already previously connected');
                        end
                        clear wrapper;
                        wrapper = PlxConnection();
                        plx = wrapper.name;

                        %Flush buffer
%                         if eventsonly == 1
%                             counts = PL_GetSpikeCounts(plx); 
%                         else
                        [ndatapoints, ts] = PL_GetTS(plx);
%                         end
                        
                        
                        %Handshake request
                        %Read IP
                        clientip = pnet(sock,'readline');
                        clientport = pnet(sock,'read',[1,1],'uint16');
                        
                        %Get the current time from the Plexon server
                        %Currently hacky: wait for a message, then set
                        %currenttime to the timestamp within this
                        %message plus the polling interval for the Plexon
                        %server
                        PL_WaitForServer(plx,100);
%                         [ndatapoints, ts, junk2] = PL_GetAD(plx); %2009a compatibility issue
%                         if eventsonly == 2
%                             ts = PL_GetSpikeCounts(plx); 
%                         else
                        [ndatapoints, ts] = PL_GetTS(plx);
%                         end
%                         allpars = PL_GetPars(plx); % broken mex
%                         functionality
                        currenttime = ts; % + ndatapoints/allpars(14); 
                        
                        
                        %connect to client and send a payload containing 
                        %the current time on the server
                        pnet(sock,'printf',['POLO' char(10)]);
                        pnet(sock,'write',currenttime);
                        %pnet(sock,'printf','Random garbagey garbage');
                        pnet(sock,'writepacket',clientip,double(clientport));
                        
                        fprintf('Client %s:%d connected\n',clientip,clientport);
                        
                        clientisconnected = 1;
                        
                        connecttime = clock;
                        
                        %Clear the spike buffer
                        [nspks,ts] = PL_GetTS(plx);
                    case 'GET'
                        packetnum=sentSpikes(plx,sock,clientip,clientport,maxpacketsize,splice_pause,eventsonly,packetnum);
                    case 'KEEPALIVE'
                        connecttime = clock;
                    case 'SETTINGS'
                        settingInstruction = pnet(sock,'readline');
                        switch settingInstruction
                            case 'EVENTSONLY'
                                eventsonly = pnet(sock,'read',[1,1],'uint8');
                            case 'CONTINUOUS'
                                continuous = pnet(sock,'read',[1,1],'uint8');
                        end
                        
                    case 'DISCONNECT'
                        clientisconnected = 0;
                        connecttime = clock + 1;

                        %close port and reopen
                        pnet('closeall')
                        break

                end
            end
            
            %Don't send spikes for no reason
            if etime(clock,connecttime) > timeout
                disp('client disconnected');
                clientisconnected = 0;
                connecttime = clock + 1;
                
                %close port and reopen
                pnet(sock,'close');
                sock=pnet('udpsocket',port);
            elseif continuous
                packetnum=sentSpikes(plx,sock,clientip,clientport,maxpacketsize,splice_pause,eventsonly,packetnum);
            end
            
        end % while loop
    end
end

function packetnum=sentSpikes(plx,sock,clientip,clientport,maxpacketsize,splice_pause,eventsonly,packetnum)
	[nspks,ts] = PL_GetTS(plx);
    if eventsonly
        ts(ts(:,1) == 1,:)=[];
        nspks=size(ts,1);
    end

	if nspks > 0 %Received spikes
        fprintf('Sending %d spikes\n', nspks);
        display(ts(:,1));
        display(ts(:,2));
        display(ts(:,3));
        display(ts(:,4));
                                                     
        %Send spikes in batches of 1000*96
        for ii = 1:ceil(size(ts,1)/maxpacketsize)
            if ii >1 %DEBUGGING
                disp('packet splicing ... if message is constant decrease port_pause and/or splice_pause in spikeserver.m')
                pause(splice_pause)
            end
            %Write the spikes to the port
            rg = (ii-1)*maxpacketsize+1:min(size(ts,1),ii*maxpacketsize);
            pnet(sock,'printf',['SPIKES' char(10)]);
            pnet(sock,'write', packetnum);
            packetnum=packetnum+1;
            %fprintf('Packet num %d\n', packetnum);
            pnet(sock,'write',ts(rg,:));
            pnet(sock,'writepacket',clientip,clientport);
        end
	end
end
