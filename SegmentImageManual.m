%%a function for manual segmentation of individual cells after tracking
%%using TrackPad
%%path is the path to the directory containing snapshots of individual
%%cells produced by TrackPad->TrackTable->Export->Cell image patches
%e.g. path XX:\Directory_where_your_trackfile_is_saved\SegmentedCells
%edited on 1st November 2018
function clone=SegmentImageManual()

[clonefilename,path]=uigetfile('.mat','Select clone file');
load([path clonefilename]);
if ~isdir([path 'SegmentedCells'])
    warndlg('SegmentedCells folder does not exist - exiting!');
    return
else
    imagepatchpath=[path '\SegmentedCells\'];
end

%prompt user for clone and tracknumb
prompt={'Start clone: '; 'End clone:'; 'Start track: '; 'End track: '};
title='Enter clone and track numbers';
defaultans={'1',num2str(length(clone)),'1','20'};
answer=inputdlg(prompt,title,1,defaultans);
clonenumb=str2num(answer{1}):str2num(answer{2});
tracknumbers=str2num(answer{3}):str2num(answer{4});


%prompt user for range of frames to segment
segmentationmode=questdlg('Which frames do you want to segment?','Frame selection','All frames', 'Range', 'First, middle, and last', 'Quit');

if strcmp(segmentationmode,'Range') %get user to enter frame numbers
    framerange=str2num(cell2mat(inputdlg('Enter frame numbers')));
    timestamps=clone{1}.TimeStamps(framerange); %get timestamps from clone
    
elseif strcmp(segmentationmode,'Quit')
    return
    
end

%loop through all clones
for h=1:length(clonenumb)
    disp(['Processing clone ' num2str(clonenumb(h))]);
    
    currentclone=clonenumb(h); %get current clone
    %check how many tracks are in current clone, if less than tracknumb then adjust
    if length(clone{currentclone}.track)<max(tracknumbers)
        tracknumb=min(tracknumbers):length(clone{currentclone}.track);
        disp(['Clone ' num2str(currentclone)...
            ' only has ' num2str(length(tracknumb))...
            ' tracks -> processing ' num2str(length(tracknumb)) ' tracks']);
    else
        tracknumb=tracknumbers;
    end
    
    %loop through all tracks
    for i=1:length(tracknumb)
        disp(['Processing track ' num2str(tracknumb(i))]);
        
        %get snapshot files and sort framenumbers
        files=dir([imagepatchpath 'Clone ' num2str(currentclone) '\Track' num2str(tracknumb(i)) '\Phase\' '*.tif']);
        
        S1p = [files(:).datenum].';  % eliminate . and .. first.
        [S1p,S1p] = sort(S1p);
        S1p = {files(S1p).name};  % Cell array of names in order by datenum.
        S1p=cellstr(S1p);
        
        framenumbers=sort(cellfun(@GetFrameNumb,S1p));
        
        switch segmentationmode
            
            case 'All'
                
                framenumbers=min(framenumbers):max(framenumbers);
                
            case 'Range'
                
                ndx=arrayfun(@(x) find(x==clone{currentclone}.track{tracknumb(i)}.T),timestamps,'UniformOutput',0); %find relative frame numbers
                framenumbers=[ndx{:}];
                
            case  'First, middle, and last'
                
                %only take first, middle, and last frames
                if max(framenumbers)>=20
                    framenumbers=[(min(framenumbers)+5) round(median(framenumbers(5:end-10))) (max(framenumbers)-10)];
                elseif max(framenumbers)<=20 && max(framenumbers)>2
                    framenumbers=[min(framenumbers) round(median(framenumbers)) (max(framenumbers)-2)];
                end
                
        end
        
        
        %loop through framenumbers
        for j=1:length(framenumbers)
            
            %get current framenumb
            framenumb=framenumbers(j);
            
            disp(['Processing frame ' num2str(framenumb)]);
            
            %get individual cell snapshot to be used for segmentation
            im=imread([imagepatchpath 'Clone ' num2str(currentclone) '\Track' num2str(tracknumb(i))...
                '\Phase\Frame ' num2str(framenumb) '.TIF']);
            
            %%start segmentation
            if ~isfield(clone{currentclone}.track{tracknumb(i)},'cegmentedmasks')
                clone{currentclone}.track{tracknumb(i)}.cegmentedmasks=...
                    cell(1,length(clone{currentclone}.track{tracknumb(i)}.T));
                [clone,exitflag]=ManualSegmentation(clone,im,currentclone,tracknumb(i),framenumb);
            elseif ~isempty(clone{currentclone}.track{tracknumb(i)}.cegmentedmasks{framenumb})
                answer=questdlg('Create new mask?','Mask already exists');
                
                switch answer
                    case 'No'
                        disp(['Skipping clone ' num2str(currentclone) ' track ' num2str(tracknumb(i)) ' frame '...
                            num2str(framenumb)]);
                        exitflag=0;
                    case 'Yes'
                        [clone,exitflag]=ManualSegmentation(clone,im,currentclone,tracknumb(i),framenumb);
                    case 'Cancel'
                        disp(['Skipping clone ' num2str(currentclone) ' track ' num2str(tracknumb(i))]);
                        exitflag=1;
                end
            else
                [clone,exitflag]=ManualSegmentation(clone,im,currentclone,tracknumb(i),framenumb);
            end
            %save and exit
            if exitflag==1
                disp('Saving clone file');
                save([path clonefilename],'clone');
                return
            end
        end
    end
    
end
disp('Saving clone file');
save([path clonefilename],'clone');
end


%%manual segmentation function
function [clone,exitflag]=ManualSegmentation(clone,im,clonenumb,track,framenumb)
%open figure and subplot
fh=figure();
% fh.CloseRequestFcn={CloseFigure,obj};
fh2=subplot(1,2,1);
trackid=clone{clonenumb}.track{track}.TrackNum;
imshow(im,[]); title(sprintf('Freehand draw around the cell\n Clone %d track %d frame %d',...
    clonenumb,trackid,framenumb));
set(gcf, 'Position', get(0, 'Screensize'));

%create callback buttons containing userdata variable
finish=uicontrol('Parent',fh,'Position', [50 450 100 40], 'String', 'Finish segmentation','ForegroundColor','g', ...
    'BackgroundColor','k','UserData',zeros(1),'Callback', @FinishButton);
cont=uicontrol('Parent',fh,'Position', [50 500 100 40], 'String', 'Continue segmentation','ForegroundColor','g', ...
    'BackgroundColor','k','UserData',zeros(1),'Callback', @ContinueButton);
saveandexit=uicontrol('Parent',fh,'Position', [50 550 100 40], 'String', 'Save and exit','ForegroundColor','g', ...
    'BackgroundColor','k','UserData',zeros(1),'Callback', @SaveButton);
start=uicontrol('Parent',fh,'Style','togglebutton','Position', [50 600 100 40],'ForegroundColor','g',...
    'BackgroundColor','k','String', 'Start segmentation','UserData',zeros(1),'Callback', @SegmentButton);
fill=uicontrol('Parent',fh,'Position', [50 400 100 40], 'String', 'Dilate and fill', ...
    'ForegroundColor','g','BackgroundColor','k','UserData',struct('fillflag',zeros(1)),'Callback', @FillButton);
undofill=uicontrol('Parent',fh,'Position', [50 350 100 40], 'String', 'Undo dilate and fill',...
    'ForegroundColor','g','BackgroundColor','k','UserData',struct('undoflag',zeros(1)),'Callback', @UndoFillButton);
%%wait for user to start segmentation (i.e. presses start segmentation
%%button) or save and exit (i.e. press save and exit button)
uiwait(gcf);
if saveandexit.UserData==1
    close(fh);
    exitflag=1;
    return
elseif start.UserData==1&&saveandexit.UserData==0
    
    %any errors are caught - clone is saved and function exits
    try
        while (start.UserData==1)
            imagehandle=imfreehand(fh2,'Closed',0);
            masksegment=createMask(imagehandle);
            wholemask=false;
            wholemask = masksegment | wholemask;
            subplot(1,2,2);
            imshow(wholemask,[]); title('Binary mask');
            %if user chooses to continue segmentation allow them to continually draw
            %using imfreehand until finished
            while(finish.UserData==0)
                uiwait(gcf);
                if(cont.UserData==1)
                    imagehandle= imfreehand(fh2,'Closed',0);
                    masksegment = createMask( imagehandle );
                    wholemask = masksegment | wholemask;
                    subplot(1,2,2);
                    imshow(wholemask,[]); title('Binary mask');
                    uiwait(gcf);
                end
                if (fill.UserData.fillflag==1)
                    tempmask=wholemask;
                    wholemask=imdilate(wholemask,strel('line',4,0));
                    wholemask=imdilate(wholemask,strel('line',4,90));
                    wholemask=imfill(wholemask,'Holes');
                    fill.UserData.fillflag=0;
                    imshow(wholemask,[]); title('Binary mask');
                    uiwait(gcf);
                end
                if (undofill.UserData.undoflag==1)
                    wholemask=tempmask;
                    undofill.UserData.undoflag=0;
                    imshow(wholemask,[]); title('Binary mask');
                    uiwait(gcf);
                end
            end
            %close figure and annotate clone file when segmentation has finished
            close(fh);
            clone{clonenumb}.track{track}.cegmentedmasks{framenumb}=wholemask;
            %exitflag not raised - do not exit and save
            exitflag=0;
            return
        end
        %any errors are caught-save clone and exit
    catch
        disp('Error - exiting SegmentImageManual and saving clone file');
        close(fh);
        exitflag=1;
        return
    end
end
end


%%callbacks for ManualSegmentation%%
%finish button callback
function FinishButton(source,callbackdata)
source.UserData=1;
uiresume(gcbf);
end

%continue button callback
function ContinueButton(source,callbackdata)
source.UserData=1;
uiresume(gcbf);
end

%start segment button call back
function SegmentButton(source,callbackdata)
uiresume(gcbf);
source.UserData=1;
end

%save and exit button call back
function SaveButton(source,callbackdata)
source.UserData=1;
uiresume(gcbf);
end

%fill button call back
function FillButton(source,callbackdata)
source.UserData.fillflag=1;
uiresume(gcbf);
end

%undo fill button call back
function UndoFillButton(source,callbackdata)
source.UserData.undoflag=1;
uiresume(gcbf);
end