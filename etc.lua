require 'image'
torch.setdefaulttensortype('torch.FloatTensor')
local Class ={'aeroplane','bicycle','bird','boat','bottle','bus','car',
           'cat','chair','cow','diningtable','dog','horse','motorbike',
           'person','pottedplant','sheep','sofa','train','tvmonitor'}


-------------------------------------------------------
function class2num(class)


for k,v  in pairs(Class) do
  
  if v == class then 
                   
          return k end
end        

assert(nil,'wrong class name')

end

function num2class(num ) return Class[num] end
-----------------------------------------------------------

function jaccard(anno1,anno2)

local xmin, xmax = torch.cmax(anno1[{{1}}],anno2[{{1}}]), torch.cmin(anno1[{{3}}],anno2[{{3}}])
local ymin, ymax = torch.cmax(anno1[{{2}}], anno2[{{2}}]), torch.cmin(anno1[{{4}}],anno2[{{4}}])

local I = torch.cmax(xmax-xmin,0):cmul( torch.cmax(ymax-ymin,0))

local U = (anno1[{{3}}]-anno1[{{1}}]):cmul(anno1[{{4}}]-anno1[{{2}}])  + (anno2[{{3}}]-anno2[{{1}}]):cmul(anno2[{{4}}]-anno2[{{2}}]) - I 

return I:cdiv(U)
end

--end

-----------------------------------------------------------
function jaccard_matrix(tensor,gt) 
if tensor:dim() ==4 then
gt:resize(4,1,1,1)
end

local expandGt = gt:expandAs(tensor) -- 4 by ~

local xdelta = torch.cmin(tensor[{{3}}],expandGt[{{3}}])-
torch.cmax(tensor[{{1}}],expandGt[{{1}}])
local ydelta = torch.cmax(tensor[{{4}}],expandGt[{{4}}])-
torch.cmax(tensor[{{2}}],expandGt[{{2}}])

local I = xdelta:cmul(ydelta)

local tensor_size = tensor:size(); tensor_size[1]=1
local tensor_element = torch.numel(tensor[{{1}}])
local t_t = (tensor[{{3}}]-tensor[{{1}}]):reshape(tensor_element)
t_t:cmul(tensor[{{4}}]-tensor[{{2}}]:reshape(tensor_element))

gt=gt:squeeze()
local U =t_t:reshape(tensor_size)+(gt[{{3}}]-gt[{{1}}])*(gt[{{4}}]-gt[{{2}}]) - I



return I:cdiv(U)

end




-- Non-maximum suppression (NMS)
--
-- Greedily skip boxes that are significantly overlapping a previously 
-- selected box.
--
-- Arguments
--   boxes     Bounding boxes as nx4 tensor, each row specifies the
--             vertices of one box { min_x, min_y, max_x, max_y }. 
--   overlap   Intersection-over-union (IoU) threshold for suppression,
--             all boxes with va alues higher than this threshold will 
--             be suppressed.
--   scores    (optional) Defines in which order boxes are processed.
--             Either the string 'area' or a tensor holding 
--             score-values. Boxes will be processed sorted descending
--             after this value.
--
-- Return value
--   Indices of boxes remaining after non-maximum suppression.

-- Original author: Francisco Massa: https://github.com/fmassa/object-detection.torch 
-- Based on matlab code by Pedro Felzenszwalb https://github.com/rbgirshick/voc-dpm/blob/master/test/nms.m
-- Minor changes by Andreas Köpf, 2015-09-17 
function nms(boxes, overlap, scores) -- adjusted

  local score_upper = torch.gt(scores,0.01)
--  print(boxes:size(),scores:size())
  boxes = boxes[score_upper:view(-1,1):expandAs(boxes)]:view(-1,4)
  scores = scores[score_upper]
  
  local pick = torch.LongTensor()

  if boxes:numel() == 0 then
    return pick
  end

  local box_num = boxes:size(1)
  local all_pairs_iou = torch.Tensor(box_num,box_num)



  local w = boxes[{{}, {1}}]
  local h = boxes[{{}, {2}}]
  local x = boxes[{{}, {3}}]
  local y = boxes[{{}, {4}}]

  local xmax = (x+w):expand(box_num,box_num):cuda()
  xmax:cmin(xmax:t()):cmax(0):cmin(1)
  local xmin = x:expand(box_num,box_num):cuda()
  xmin:cmax(xmin:t()):cmax(0):cmin(1)
  local ymax = (y+h):expand(box_num,box_num):cuda()
  ymax:cmin(ymax:t()):cmax(0):cmin(1)
  local ymin = y:expand(box_num,box_num):cuda()
  ymin:cmax(ymin:t()):cmax(0):cmin(1)

  local inter = torch.cmul(ymax-ymin,xmax-xmin)
  ymax=nil;ymin=nil;xmax=nil;xmin=nil; collectgarbage();

  
  local area = torch.cmul(w:cuda():expand(box_num,box_num),h:cuda():expand(box_num,box_num))
  local IOU = torch.cdiv(inter,area+area:t()-inter)
  
  
  
  
  local v, I = scores:cuda():sort(1)
  I=I:float()
print(I)  

  pick:resize(box_num):zero()
  local count = 1
  --[[
  local xx1 = boxes.new()
  local yy1 = boxes.new()
  local xx2 = boxes.new()
  local yy2 = boxes.new()

  local ww = boxes.new()
  local hh = boxes.new()
]]--
  while I:numel() > 0 do 
    local last = I:size(1)
    local i = I[last]
    
    pick[count] = i
    count = count + 1
    
    if last == 1 then
      break
    end
    
    I = I[{{1, last-1}}] -- remove picked element from view
   --[[ 
    -- load values 
    xx1:index(x, 1, I)
    yy1:index(y, 1, I)
    xx2:index(x+w, 1, I)
    yy2:index(y+h, 1, I)
    
    -- compute intersection area
    xx1:cmax(x[i])
    yy1:cmax(y[i])
    xx2:cmin(x[i]+w[i])
    yy2:cmin(y[i]+h[i])
    
--    ww:index(w,1,I) 
--    hh:index(h,1,I)

--    torch.add(w, xx2, -1, xx1):add(1):cmax(0)
--    torch.add(h, yy2, -1, yy1):add(1):cmax(0)
    
    -- reuse existing tensors
    local inter = (xx2-xx1):cmul(yy2-yy1):cmax(0)
    local IoU = inter:cdiv(area:index(1,I)+area[i]-inter)
    
    -- IoU := i / (area(a) + area(b) - i)
--    xx1:index(area, 1, I) -- load remaining areas into xx1
--    torch.cdiv(IoU, inter, xx1 + area[i] - inter) -- store result in iou
    ]]--

    local partial_IoU = IOU[i]
    I = I[partial_IoU:le(overlap)] -- keep only elements with a IoU < overlap 
  end

  -- reduce size to actual count
  pick = pick[{{1, count-1}}]
  return boxes:index(1,pick)
end
