
precision mediump float;
precision mediump int;

#define max_clip_polygons 8
#define PI 3.141592653589793

attribute vec3 position;
attribute vec3 color;
attribute float intensity;
attribute float classification;
attribute float returnNumber;
attribute float numberOfReturns;
attribute float pointSourceID;
attribute vec4 index;

uniform mat4 modelMatrix;
uniform mat4 modelViewMatrix;
uniform mat4 projectionMatrix;
uniform mat4 viewMatrix;

uniform float uScreenWidth;
uniform float uScreenHeight;
uniform float fov;
uniform float near;
uniform float far;

uniform bool uUseOrthographicCamera;
uniform float uOrthoWidth;
uniform float uOrthoHeight;

uniform int clipMode;
#if defined(num_clipboxes) && num_clipboxes > 0
	uniform mat4 clipBoxes[num_clipboxes];
#endif

#if defined(num_clippolygons) && num_clippolygons > 0
	uniform int uClipPolygonVCount[num_clippolygons];
	uniform vec3 uClipPolygonVertices[num_clippolygons * 8];
	uniform mat4 uClipPolygonVP[num_clippolygons];
#endif

uniform float size;
uniform float minSize;
uniform float maxSize;

uniform float uPCIndex;
uniform float uOctreeSpacing;
uniform float uNodeSpacing;
uniform float uOctreeSize;
uniform vec3 uBBSize;
uniform float uLevel;
uniform float uVNStart;

uniform vec3 uColor;
uniform float uOpacity;

uniform vec2 elevationRange;
uniform vec2 intensityRange;
uniform float intensityGamma;
uniform float intensityContrast;
uniform float intensityBrightness;
uniform float rgbGamma;
uniform float rgbContrast;
uniform float rgbBrightness;
uniform float uTransition;
uniform float wRGB;
uniform float wIntensity;
uniform float wElevation;
uniform float wClassification;
uniform float wReturnNumber;
uniform float wSourceID;

uniform vec3 uShadowColor;


uniform sampler2D visibleNodes;
uniform sampler2D gradient;
uniform sampler2D classificationLUT;

#if defined(num_shadowmaps) && num_shadowmaps > 0
uniform sampler2D uShadowMap[num_shadowmaps];
uniform mat4 uShadowWorldView[num_shadowmaps];
#endif

#if defined(num_snapshots) && num_snapshots > 0
uniform sampler2D uSnapshot[num_snapshots];
uniform mat4 uSnapView[num_snapshots];
uniform mat4 uSnapProj[num_snapshots];
uniform mat4 uSnapScreenToCurrentView[num_snapshots];

varying vec4 vSnapProjected[num_snapshots];
varying float vSnapProjectedDistance[num_snapshots];
#endif

varying vec3	vColor;
varying float	vLinearDepth;
varying float	vLogDepth;
varying vec3	vViewPosition;
varying float 	vRadius;
varying vec3	vWorldPosition;
varying float 	vPointSize;


float round(float number){
	return floor(number + 0.5);
}

// 
//    ###    ########     ###    ########  ######## #### ##     ## ########     ######  #### ######## ########  ######  
//   ## ##   ##     ##   ## ##   ##     ##    ##     ##  ##     ## ##          ##    ##  ##       ##  ##       ##    ## 
//  ##   ##  ##     ##  ##   ##  ##     ##    ##     ##  ##     ## ##          ##        ##      ##   ##       ##       
// ##     ## ##     ## ##     ## ########     ##     ##  ##     ## ######       ######   ##     ##    ######    ######  
// ######### ##     ## ######### ##           ##     ##   ##   ##  ##                ##  ##    ##     ##             ## 
// ##     ## ##     ## ##     ## ##           ##     ##    ## ##   ##          ##    ##  ##   ##      ##       ##    ## 
// ##     ## ########  ##     ## ##           ##    ####    ###    ########     ######  #### ######## ########  ######  
// 																			


// ---------------------
// OCTREE
// ---------------------

#if (defined(adaptive_point_size) || defined(color_type_lod)) && defined(tree_type_octree)
/**
 * number of 1-bits up to inclusive index position
 * number is treated as if it were an integer in the range 0-255
 *
 */
int numberOfOnes(int number, int index){
	int numOnes = 0;
	int tmp = 128;
	for(int i = 7; i >= 0; i--){
		
		if(number >= tmp){
			number = number - tmp;

			if(i <= index){
				numOnes++;
			}
		}
		
		tmp = tmp / 2;
	}

	return numOnes;
}


/**
 * checks whether the bit at index is 1
 * number is treated as if it were an integer in the range 0-255
 *
 */
bool isBitSet(int number, int index){

	// weird multi else if due to lack of proper array, int and bitwise support in WebGL 1.0
	int powi = 1;
	if(index == 0){
		powi = 1;
	}else if(index == 1){
		powi = 2;
	}else if(index == 2){
		powi = 4;
	}else if(index == 3){
		powi = 8;
	}else if(index == 4){
		powi = 16;
	}else if(index == 5){
		powi = 32;
	}else if(index == 6){
		powi = 64;
	}else if(index == 7){
		powi = 128;
	}else{
		return false;
	}

	int ndp = number / powi;

	return mod(float(ndp), 2.0) != 0.0;
}


/**
 * find the LOD at the point position
 */
float getLOD(){
	
	vec3 offset = vec3(0.0, 0.0, 0.0);
	int iOffset = int(uVNStart);
	float depth = uLevel;
	for(float i = 0.0; i <= 30.0; i++){
		float nodeSizeAtLevel = uOctreeSize  / pow(2.0, i + uLevel + 0.0);
		
		vec3 index3d = (position-offset) / nodeSizeAtLevel;
		index3d = floor(index3d + 0.5);
		int index = int(round(4.0 * index3d.x + 2.0 * index3d.y + index3d.z));
		
		vec4 value = texture2D(visibleNodes, vec2(float(iOffset) / 2048.0, 0.0));
		int mask = int(round(value.r * 255.0));

		if(isBitSet(mask, index)){
			// there are more visible child nodes at this position
			int advanceG = int(round(value.g * 255.0)) * 256;
			int advanceB = int(round(value.b * 255.0));
			int advanceChild = numberOfOnes(mask, index - 1);
			int advance = advanceG + advanceB + advanceChild;

			iOffset = iOffset + advance;
			
			depth++;
		}else{
			// no more visible child nodes at this position
			return depth;
		}
		
		offset = offset + (vec3(1.0, 1.0, 1.0) * nodeSizeAtLevel * 0.5) * index3d;
	}
		
	return depth;
}

float getSpacing(){
	vec3 offset = vec3(0.0, 0.0, 0.0);
	int iOffset = int(uVNStart);
	float depth = uLevel;
	float spacing = uNodeSpacing;
	for(float i = 0.0; i <= 30.0; i++){
		float nodeSizeAtLevel = uOctreeSize  / pow(2.0, i + uLevel + 0.0);
		
		vec3 index3d = (position-offset) / nodeSizeAtLevel;
		index3d = floor(index3d + 0.5);
		int index = int(round(4.0 * index3d.x + 2.0 * index3d.y + index3d.z));
		
		vec4 value = texture2D(visibleNodes, vec2(float(iOffset) / 2048.0, 0.0));
		int mask = int(round(value.r * 255.0));
		float spacingFactor = value.a;

		if(i > 0.0){
			spacing = spacing / (255.0 * spacingFactor);
		}
		

		if(isBitSet(mask, index)){
			// there are more visible child nodes at this position
			int advanceG = int(round(value.g * 255.0)) * 256;
			int advanceB = int(round(value.b * 255.0));
			int advanceChild = numberOfOnes(mask, index - 1);
			int advance = advanceG + advanceB + advanceChild;

			iOffset = iOffset + advance;

			//spacing = spacing / (255.0 * spacingFactor);
			//spacing = spacing / 3.0;
			
			depth++;
		}else{
			// no more visible child nodes at this position
			return spacing;
		}
		
		offset = offset + (vec3(1.0, 1.0, 1.0) * nodeSizeAtLevel * 0.5) * index3d;
	}
		
	return spacing;
}

float getPointSizeAttenuation(){
	return pow(2.0, getLOD());
}


#endif


// ---------------------
// KD-TREE
// ---------------------

#if (defined(adaptive_point_size) || defined(color_type_lod)) && defined(tree_type_kdtree)

float getLOD(){
	vec3 offset = vec3(0.0, 0.0, 0.0);
	float iOffset = 0.0;
	float depth = 0.0;
		
		
	vec3 size = uBBSize;	
	vec3 pos = position;
		
	for(float i = 0.0; i <= 1000.0; i++){
		
		vec4 value = texture2D(visibleNodes, vec2(iOffset / 2048.0, 0.0));
		
		int children = int(value.r * 255.0);
		float next = value.g * 255.0;
		int split = int(value.b * 255.0);
		
		if(next == 0.0){
		 	return depth;
		}
		
		vec3 splitv = vec3(0.0, 0.0, 0.0);
		if(split == 1){
			splitv.x = 1.0;
		}else if(split == 2){
		 	splitv.y = 1.0;
		}else if(split == 4){
		 	splitv.z = 1.0;
		}
		
		iOffset = iOffset + next;
		
		float factor = length(pos * splitv / size);
		if(factor < 0.5){
			// left
		if(children == 0 || children == 2){
				return depth;
			}
		}else{
			// right
			pos = pos - size * splitv * 0.5;
			if(children == 0 || children == 1){
				return depth;
			}
			if(children == 3){
				iOffset = iOffset + 1.0;
			}
		}
		size = size * ((1.0 - (splitv + 1.0) / 2.0) + 0.5);
		
		depth++;
	}
		
		
	return depth;	
}

float getPointSizeAttenuation(){
	return 0.5 * pow(1.3, getLOD());
}

#endif



// 
//    ###    ######## ######## ########  #### ########  ##     ## ######## ########  ######  
//   ## ##      ##       ##    ##     ##  ##  ##     ## ##     ##    ##    ##       ##    ## 
//  ##   ##     ##       ##    ##     ##  ##  ##     ## ##     ##    ##    ##       ##       
// ##     ##    ##       ##    ########   ##  ########  ##     ##    ##    ######    ######  
// #########    ##       ##    ##   ##    ##  ##     ## ##     ##    ##    ##             ## 
// ##     ##    ##       ##    ##    ##   ##  ##     ## ##     ##    ##    ##       ##    ## 
// ##     ##    ##       ##    ##     ## #### ########   #######     ##    ########  ######                                                                               
// 



// formula adapted from: http://www.dfstudios.co.uk/articles/programming/image-programming-algorithms/image-processing-algorithms-part-5-contrast-adjustment/
float getContrastFactor(float contrast){
	return (1.0158730158730156 * (contrast + 1.0)) / (1.0158730158730156 - contrast);
}

vec3 getRGB(){
	vec3 rgb = color;
	
	rgb = pow(rgb, vec3(rgbGamma));
	rgb = rgb + rgbBrightness;
	rgb = (rgb - 0.5) * getContrastFactor(rgbContrast) + 0.5;
	rgb = clamp(rgb, 0.0, 1.0);
	
	//rgb = indices.rgb;
	//rgb.b = pcIndex / 255.0;
	
	
	return rgb;
}

float getIntensity(){
	float w = (intensity - intensityRange.x) / (intensityRange.y - intensityRange.x);
	w = pow(w, intensityGamma);
	w = w + intensityBrightness;
	w = (w - 0.5) * getContrastFactor(intensityContrast) + 0.5;
	w = clamp(w, 0.0, 1.0);

	//w = w + color.x * 0.0001;
	
	//float w = color.x * 0.001 + intensity / 1.0;

	return w;
}

vec3 getElevation(){
	vec4 world = modelMatrix * vec4( position, 1.0 );
	float w = (world.z - elevationRange.x) / (elevationRange.y - elevationRange.x);
	vec3 cElevation = texture2D(gradient, vec2(w,1.0-w)).rgb;
	
	return cElevation;
}

vec4 getClassification(){
	vec2 uv = vec2(classification / 255.0, 0.5);
	vec4 classColor = texture2D(classificationLUT, uv);
	
	return classColor;
}

vec3 getReturnNumber(){
	if(numberOfReturns == 1.0){
		return vec3(1.0, 1.0, 0.0);
	}else{
		if(returnNumber == 1.0){
			return vec3(1.0, 0.0, 0.0);
		}else if(returnNumber == numberOfReturns){
			return vec3(0.0, 0.0, 1.0);
		}else{
			return vec3(0.0, 1.0, 0.0);
		}
	}
}

vec3 getSourceID(){
	float w = mod(pointSourceID, 10.0) / 10.0;
	return texture2D(gradient, vec2(w,1.0 - w)).rgb;
}

vec3 getCompositeColor(){
	vec3 c;
	float w;

	c += wRGB * getRGB();
	w += wRGB;
	
	c += wIntensity * getIntensity() * vec3(1.0, 1.0, 1.0);
	w += wIntensity;
	
	c += wElevation * getElevation();
	w += wElevation;
	
	c += wReturnNumber * getReturnNumber();
	w += wReturnNumber;
	
	c += wSourceID * getSourceID();
	w += wSourceID;
	
	vec4 cl = wClassification * getClassification();
    c += cl.a * cl.rgb;
	w += wClassification * cl.a;

	c = c / w;
	
	if(w == 0.0){
		//c = color;
		gl_Position = vec4(100.0, 100.0, 100.0, 0.0);
	}
	
	return c;
}


// 
//  ######  ##       #### ########  ########  #### ##    ##  ######   
// ##    ## ##        ##  ##     ## ##     ##  ##  ###   ## ##    ##  
// ##       ##        ##  ##     ## ##     ##  ##  ####  ## ##        
// ##       ##        ##  ########  ########   ##  ## ## ## ##   #### 
// ##       ##        ##  ##        ##         ##  ##  #### ##    ##  
// ##    ## ##        ##  ##        ##         ##  ##   ### ##    ##  
//  ######  ######## #### ##        ##        #### ##    ##  ######                                                          
// 



#if defined(num_clippolygons) && num_clippolygons > 0
bool pointInClipPolygon(vec3 point, int polyIdx) {
	vec4 screenClipPos = uClipPolygonVP[polyIdx] * modelMatrix * vec4(point, 1.0);
	screenClipPos.xy = screenClipPos.xy / screenClipPos.w * 0.5 + 0.5;

	int j = uClipPolygonVCount[polyIdx] - 1;
	bool c = false;
	for(int i = 0; i < 8; i++) {
		if(i == uClipPolygonVCount[polyIdx]) {
			break;
		}

		vec4 verti = uClipPolygonVP[polyIdx] * vec4(uClipPolygonVertices[polyIdx * 8 + i], 1);
		vec4 vertj = uClipPolygonVP[polyIdx] * vec4(uClipPolygonVertices[polyIdx * 8 + j], 1);
		verti.xy = verti.xy / verti.w * 0.5 + 0.5;
		vertj.xy = vertj.xy / vertj.w * 0.5 + 0.5;
		if( ((verti.y > screenClipPos.y) != (vertj.y > screenClipPos.y)) && 
			(screenClipPos.x < (vertj.x-verti.x) * (screenClipPos.y-verti.y) / (vertj.y-verti.y) + verti.x) ) {
			c = !c;
		}
		j = i;
	}

	return c;
}
#endif

void testInsideClipVolume(bool inside) {
	if(inside && clipMode == 2 || !inside && clipMode == 3) {
		gl_Position = vec4(1000.0, 1000.0, 1000.0, 1.0);
	} else if(clipMode == 1 && inside) {
		vColor.r += 0.5;
	}
}

vec3 getColor(){
	vec3 color;
	
	#ifdef color_type_rgb
		color = getRGB();
	#elif defined color_type_height
		color = getElevation();
	#elif defined color_type_rgb_height
		vec3 cHeight = getElevation();
		color = (1.0 - uTransition) * getRGB() + uTransition * cHeight;
	#elif defined color_type_depth
		float linearDepth = -mvPosition.z ;
		float expDepth = (gl_Position.z / gl_Position.w) * 0.5 + 0.5;
		color = vec3(linearDepth, expDepth, 0.0);
	#elif defined color_type_intensity
		float w = getIntensity();
		color = vec3(w, w, w);
	#elif defined color_type_intensity_gradient
		float w = getIntensity();
		color = texture2D(gradient, vec2(w,1.0-w)).rgb;
	#elif defined color_type_color
		color = uColor;
	#elif defined color_type_lod
		float depth = getLOD();
		float w = depth / 10.0;
		color = texture2D(gradient, vec2(w,1.0-w)).rgb;
	#elif defined color_type_point_index
		color = index.rgb;
	#elif defined color_type_classification
		vec4 cl = getClassification(); 
		color = cl.rgb;
	#elif defined color_type_return_number
		color = getReturnNumber();
	#elif defined color_type_source
		color = getSourceID();
	#elif defined color_type_normal
		color = (modelMatrix * vec4(normal, 0.0)).xyz;
	#elif defined color_type_phong
		color = color;
	#elif defined color_type_composite
		color = getCompositeColor();
	#endif
	
	return color;
}

float getPointSize(){
	float pointSize = 1.0;
	
	float slope = tan(fov / 2.0);
	float projFactor =  -0.5 * uScreenHeight / (slope * vViewPosition.z);
	
	float r = uOctreeSpacing * 1.5;
	vRadius = r;
	#if defined fixed_point_size
		pointSize = size;
	#elif defined attenuated_point_size
		if(uUseOrthographicCamera){
			pointSize = size;			
		}else{
			pointSize = pointSize * projFactor;
		}
	#elif defined adaptive_point_size
		if(uUseOrthographicCamera) {
			float worldSpaceSize = 1.5 * size * r / getPointSizeAttenuation();
			pointSize = (worldSpaceSize / uOrthoWidth) * uScreenWidth;
		} else {
			float worldSpaceSize = 1.5 * size * r / getPointSizeAttenuation();
			pointSize = worldSpaceSize * projFactor;
		}
	#endif

	pointSize = max(minSize, pointSize);
	pointSize = min(maxSize, pointSize);
	
	vRadius = pointSize / projFactor;

	return pointSize;
}

void doClipping(){

	#if !defined color_type_composite
		vec4 cl = getClassification(); 
		if(cl.a == 0.0){
			gl_Position = vec4(100.0, 100.0, 100.0, 0.0);
			
			return;
		}
	#endif

	#if defined(num_clipboxes) && num_clipboxes > 0
		if(clipMode != 0) {
			bool insideAny = false;
			for(int i = 0; i < num_clipboxes; i++){
				vec4 clipPosition = clipBoxes[i] * modelMatrix * vec4( position, 1.0 );
				bool inside = -0.5 <= clipPosition.x && clipPosition.x <= 0.5;
				inside = inside && -0.5 <= clipPosition.y && clipPosition.y <= 0.5;
				inside = inside && -0.5 <= clipPosition.z && clipPosition.z <= 0.5;
				insideAny = insideAny || inside;
			}	
			testInsideClipVolume(insideAny);
		}
	#endif

	#if defined(num_clippolygons) && num_clippolygons > 0

	
		if(clipMode != 0) {
			bool polyInsideAny = false;
			for(int i = 0; i < num_clippolygons; i++) {
				polyInsideAny = polyInsideAny || pointInClipPolygon(position, i);
			}
			testInsideClipVolume(polyInsideAny);
		}
	#endif	
}

//float step(float edge, float v){
//	return v < edge ? 0.0 : 1.0;
//}

float linearStep(float min, float max, float v){
	return clamp((v - min) / (max - min), 0.0, 1.0);
}


// 
// ##     ##    ###    #### ##    ## 
// ###   ###   ## ##    ##  ###   ## 
// #### ####  ##   ##   ##  ####  ## 
// ## ### ## ##     ##  ##  ## ## ## 
// ##     ## #########  ##  ##  #### 
// ##     ## ##     ##  ##  ##   ### 
// ##     ## ##     ## #### ##    ## 
//

void main() {
	vec4 mvPosition = modelViewMatrix * vec4( position, 1.0 );
	vViewPosition = mvPosition.xyz;
	gl_Position = projectionMatrix * mvPosition;
	vLinearDepth = gl_Position.w;
	vLogDepth = log2(-mvPosition.z);


	// POINT SIZE
	float pointSize = getPointSize();
	gl_PointSize = pointSize;
	vPointSize = pointSize;

	// COLOR
	vColor = getColor();

	// CLIPPING
	doClipping();

	
	


	

	#if defined(num_snapshots) && num_snapshots > 0

		for(int i = 0; i < num_snapshots; i++){
			vSnapProjected[i] = uSnapProj[i] * uSnapView[i] * modelMatrix * vec4(position, 1.0);	
			vSnapProjectedDistance[i] = -(uSnapView[i] * modelMatrix * vec4(position, 1.0)).z;
		}
		
	#endif



	#if defined(num_shadowmaps) && num_shadowmaps > 0

		const float sm_near = 0.1;
		const float sm_far = 1000.0;

		for(int i = 0; i < num_shadowmaps; i++){
			vec3 viewPos = (uShadowWorldView[i] * vec4(position, 1.0)).xyz;
			float distanceToLight = length(viewPos);
			float u = atan(viewPos.y, viewPos.x) / PI;
			float v = atan(viewPos.z, length(viewPos.xy)) / PI;
			float distance = length(viewPos);
			float depth = ((distance - sm_near) / (sm_far - sm_near));

			vec2 uv = vec2(u, v) * 0.5 + 0.5;
			vec2 sampleStep = vec2(1.0 / (4.0*1024.0), 1.0 / (4.0*1024.0));

			vec2 sampleLocations[9];
			sampleLocations[0] = vec2(0.0, 0.0);
			sampleLocations[1] = sampleStep;
			sampleLocations[2] = -sampleStep;
			sampleLocations[3] = vec2(sampleStep.x, -sampleStep.y);
			sampleLocations[4] = vec2(-sampleStep.x, sampleStep.y);

			sampleLocations[5] = vec2(0.0, sampleStep.y);
			sampleLocations[6] = vec2(0.0, -sampleStep.y);
			sampleLocations[7] = vec2(sampleStep.x, 0.0);
			sampleLocations[8] = vec2(-sampleStep.x, 0.0);

			float visible_samples = 0.0;
			float sumSamples = 0.0;

			float bias = vRadius * 1.0;
			for(int j = 0; j < 9; j++){

				vec2 moments = texture2D(uShadowMap[j], uv + sampleLocations[j]).xy + sm_near;
				//float p = smoothstep(distanceToLight - 10.0 * bias, distanceToLight, moments.x);
				float p = step(distanceToLight - 5.0 * bias, moments.x);

				visible_samples += (1.0 - p);


				sumSamples = sumSamples + 1.0;
			}

			float coverage = 1.0 - visible_samples / sumSamples;
			float shade = coverage * 0.5 + 0.5;

			vColor = vColor * shade + uShadowColor * (1.0 - shade);
		}

	#endif

}
