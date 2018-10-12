// To compile:
// g++ capture_slide.cpp -lopencv_core -lopencv_imgproc -lopencv_objdetect -lopencv_highgui -o /tmp/capture_slide
// g++ capture_slide.cpp -lopencv_core -lopencv_imgproc -lopencv_objdetect -lopencv_highgui -lopencv_imgcodecs 

#include "opencv2/core/core.hpp"
#include "opencv2/imgproc/imgproc.hpp"
#include "opencv2/highgui/highgui.hpp"

#include <algorithm>
#include <iostream>
#include <math.h>

using namespace cv;
using namespace std;

struct AreaCmp {
    AreaCmp(const vector<float>& _areas) : areas(&_areas) {}
    bool operator()(int a, int b) const { return (*areas)[a] > (*areas)[b]; }
    const vector<float>* areas;
};


int thresh = 50, N = 11;

// helper function:
// finds a cosine of angle between vectors
// from pt0->pt1 and from pt0->pt2
static double angle(Point pt1, Point pt2, Point pt0)
{
    double dx1 = pt1.x - pt0.x;
    double dy1 = pt1.y - pt0.y;
    double dx2 = pt2.x - pt0.x;
    double dy2 = pt2.y - pt0.y;
    return (dx1*dx2 + dy1*dy2)/sqrt((dx1*dx1 + dy1*dy1)*(dx2*dx2 + dy2*dy2) + 1e-10);
}

// returns sequence of squares detected on the image.
// the sequence is stored in the specified memory storage
static void findSquares(const Mat& image, vector<vector<Point> >& squares)
{
    squares.clear();

    Mat pyr, timg, gray0(image.size(), CV_8U), gray;

    // down-scale and upscale the image to filter out the noise
    pyrDown(image, pyr, Size(image.cols/2, image.rows/2));
    pyrUp(pyr, timg, image.size());
    vector<vector<Point> > contours;

    // find squares in every color plane of the image
    for(int c = 0; c < 3; c++){
        int ch[] = {c, 0};
        mixChannels(&timg, 1, &gray0, 1, ch, 1);

        // try several threshold levels
        for(int l = 0; l < N; l++){
            // hack: use Canny instead of zero threshold level.
            // Canny helps to catch squares with gradient shading
            if(l == 0){
                // apply Canny. Take the upper threshold from slider
                // and set the lower to 0 (which forces edges merging)
                Canny(gray0, gray, 0, thresh, 5);
                // dilate canny output to remove potential
                // holes between edge segments
                dilate(gray, gray, Mat(), Point(-1,-1));
            }else{
                // apply threshold if l!=0:
                //     tgray(x,y) = gray(x,y) < (l+1)*255/N ? 255 : 0
                gray = gray0 >= (l+1)*255/N;
            }

            // find contours and store them all as a list
            findContours(gray, contours, CV_RETR_LIST, CV_CHAIN_APPROX_SIMPLE);

            vector<Point> approx;

            // test each contour
            for(size_t i = 0; i < contours.size(); i++){
                // approximate contour with accuracy proportional
                // to the contour perimeter
                approxPolyDP(Mat(contours[i]), approx, arcLength(Mat(contours[i]), true)*0.02, true);

                // square contours should have 4 vertices after approximation
                // relatively large area (to filter out noisy contours)
                // and be convex.
                // Note: absolute value of an area is used because
                // area may be positive or negative - in accordance with the
                // contour orientation
                if(approx.size() == 4 &&
                    fabs(contourArea(Mat(approx))) > 1000 &&
                    isContourConvex(Mat(approx))){
                    double maxCosine = 0;

                    for(int j = 2; j < 5; j++){
                        // find the maximum cosine of the angle between joint edges
                        double cosine = fabs(angle(approx[j%4], approx[j-2], approx[j-1]));
                        maxCosine = MAX(maxCosine, cosine);
                    }

                    // if cosines of all angles are small
                    // (all angles are ~90 degree) then write quadrangle
                    // vertices to resultant sequence
                    if(maxCosine < 0.3){
                        squares.push_back(approx);
                    }
                }
            }
        }
    }
}


// the function finds the rect_elem_index biggest rectangular area in the image [the slide POD] and generates a new image out of it
static void createSlide(Mat& image, const char *slide_output_path,const vector<vector<Point> >& squares, int rect_elem_index)
{
    vector<int> sortIdx(squares.size());
    vector<float> areas(squares.size());
    for(int n = 0; n < (int)squares.size(); n++) {
        sortIdx[n] = n;
        areas[n] = contourArea(squares[n], false);
    }

    // sort contours so that the largest contours go first
    std::sort(sortIdx.begin(), sortIdx.end(), AreaCmp(areas));
    Rect r = boundingRect(squares[sortIdx[rect_elem_index]]);
    Mat ROI(image, r);
    Mat croppedImage;

    // Copy the data into new matrix
    ROI.copyTo(croppedImage);
    // uncomment if you want to debug interactively
    //imshow("image", croppedImage);
    imwrite(slide_output_path,croppedImage);
}


int main(int argc, char** argv)
{

    if (argc < 3){
        cout<<"Usage: "<<argv[0]<<" </path/to/orig/image> </path/to/output/slide/img>\n";
        return 1;
    }
    const char *orig_img=argv[1];
    const char *slide_output_path=argv[2];
    int rect_elem_index=2;
    if (argv[3]){
        rect_elem_index=atoi(argv[3]);
    }
    vector<vector<Point> > squares;

    Mat image = imread(orig_img, 1);
    if(image.empty()){
        cout << "Couldn't load " << orig_img << endl;
    return 2;
    }

    findSquares(image, squares);
    createSlide(image, slide_output_path, squares, rect_elem_index);

    return 0;
}
